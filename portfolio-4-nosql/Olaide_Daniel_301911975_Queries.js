// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Student : Olaide Daniel (301911975)
// File    : Document queries, aggregation pipelines and graph traversal
// Run     : mongosh hdmb --quiet --file Olaide_Daniel_301911975_Queries.js
// =====================================================================
const db = db.getSiblingDB('hdmb');

function hr(t) { print(''); print('='.repeat(70)); print(t); print('='.repeat(70)); }

const ACCT = '0000001317';
const ACCT2 = '0000001318';
const CUST = 1317;

// summarise an explain plan: the four numbers that actually matter
function planOf(explain) {
    const ex = explain.executionStats || (explain.stages && explain.stages[0].$cursor.executionStats);
    const win = (explain.queryPlanner || explain.stages[0].$cursor.queryPlanner).winningPlan;
    function stages(p, acc) {
        acc.push(p.stage + (p.indexName ? '(' + p.indexName + ')' : ''));
        const next = p.inputStage || (p.queryPlan && p.queryPlan) || null;
        if (next) stages(next, acc);
        return acc;
    }
    const chain = stages(win.queryPlan || win, []).join(' <- ');
    return {
        plan: chain,
        docsExamined: ex ? ex.totalDocsExamined : null,
        keysExamined: ex ? ex.totalKeysExamined : null,
        returned: ex ? ex.nReturned : null,
        ms: ex ? ex.executionTimeMillis : null
    };
}

// -------------------------------------------------------------------
hr('M1  MOBILE HOME SCREEN - one document, no joins');
// In the relational model this screen needs customer + account +
// account_product + branch joined, plus a second query for the statement.
// Here it is a single primary-key-style read on an indexed field.
const t0 = Date.now();
const profile = db.customer_profile.findOne({ customer_id: CUST });
print('wall-clock ms            : ' + (Date.now() - t0));
print('customer                 : ' + profile.name.full + '  (' + profile.branch.code + ')');
print('accounts in the document : ' + profile.accounts.length);
print('balance                  : NGN ' + profile.accounts[0].balance.toString());
print('recent_activity embedded : ' + profile.recent_activity.length + ' postings');
print('joins required           : 0');
printjson(planOf(db.customer_profile.find({ customer_id: CUST }).explain('executionStats')));

// -------------------------------------------------------------------
hr('M2  WHO OWNS THIS ACCOUNT? - multikey index on an embedded array');
// accounts is an array inside the document; the index covers every element,
// so this is a seek and not a 1,988-document scan.
const owner = db.customer_profile.findOne(
    { 'accounts.account_number': ACCT },
    { 'name.full': 1, phone: 1, 'branch.code': 1, 'accounts.account_number': 1, 'accounts.balance': 1 });
printjson(owner);
printjson(planOf(db.customer_profile.find({ 'accounts.account_number': ACCT }).explain('executionStats')));

// -------------------------------------------------------------------
hr('M3  ACCOUNT STATEMENT - the 20 newest events for one account');
// Equivalent of Portfolio 2 Q2. The compound index (legs.account_number,
// created_at: -1) serves both the match and the sort, so there is no
// in-memory SORT stage.
const stmt = db.txn_event.find(
    { 'legs.account_number': ACCT },
    { txn_type: 1, channel: 1, status: 1, amount: 1, created_at: 1 })
    .sort({ created_at: -1 }).limit(20).toArray();
print('rows returned: ' + stmt.length);
stmt.slice(0, 5).forEach(d => print('  ' + d.created_at.toISOString().slice(0, 19) + '  ' +
    d.txn_type.padEnd(11) + d.channel.padEnd(8) + 'NGN ' + d.amount.toString()));
printjson(planOf(db.txn_event.find({ 'legs.account_number': ACCT })
    .sort({ created_at: -1 }).limit(20).explain('executionStats')));

// -------------------------------------------------------------------
hr('M4  CHANNEL DASHBOARD - aggregation pipeline (equivalent of SQL Q3)');
const dash = db.txn_event.aggregate([
    { $match: { created_at: { $gte: new Date(Date.now() - 90 * 86400000) } } },
    { $group: {
        _id: '$channel',
        attempted: { $sum: 1 },
        succeeded: { $sum: { $cond: [{ $eq: ['$status', 'SUCCESS'] }, 1, 0] } },
        failed:    { $sum: { $cond: [{ $eq: ['$status', 'FAILED'] }, 1, 0] } },
        value_moved: { $sum: { $cond: [{ $eq: ['$status', 'SUCCESS'] }, '$amount', Decimal128('0')] } }
    } },
    { $addFields: { failure_pct: { $round: [{ $multiply: [{ $divide: ['$failed', '$attempted'] }, 100] }, 2] } } },
    { $sort: { failure_pct: -1 } }
]).toArray();
dash.forEach(d => print('  ' + d._id.padEnd(8) + 'attempted ' + String(d.attempted).padStart(6) +
    '   failed ' + String(d.failed).padStart(4) + '   failure% ' + String(d.failure_pct).padStart(5) +
    '   value NGN ' + d.value_moved.toString()));

// -------------------------------------------------------------------
hr('M5  TOP DEBIT OUTFLOW - $unwind over the embedded legs (SQL Q4)');
const outflow = db.txn_event.aggregate([
    { $match: { status: 'SUCCESS', created_at: { $gte: new Date(Date.now() - 30 * 86400000) } } },
    { $unwind: '$legs' },
    { $match: { 'legs.direction': 'DR', 'legs.product_code': { $ne: 'TILL' } } },
    { $group: { _id: '$legs.account_number', debit_count: { $sum: 1 },
                total_out: { $sum: '$legs.amount' } } },
    { $sort: { total_out: -1 } },
    { $limit: 10 }
]).toArray();
outflow.forEach(d => print('  ' + d._id + '   debits ' + String(d.debit_count).padStart(3) +
    '   out NGN ' + d.total_out.toString()));

// -------------------------------------------------------------------
hr('M6  DERIVED EDGE COLLECTION - a pipeline that writes ($merge)');
// Building a graph view of the ledger: one edge per internal transfer,
// debited account -> credited account. $merge writes the result of the
// pipeline into a collection, which is MongoDB's equivalent of the
// materialised view used in Portfolio 2.
const mergeStart = Date.now();
db.txn_event.aggregate([
    { $match: { txn_type: 'TRANSFER', status: 'SUCCESS' } },
    { $project: {
        from: { $first: { $filter: { input: '$legs', as: 'l', cond: { $eq: ['$$l.direction', 'DR'] } } } },
        to:   { $first: { $filter: { input: '$legs', as: 'l', cond: { $eq: ['$$l.direction', 'CR'] } } } },
        amount: 1, created_at: 1 } },
    { $project: {
        _id: '$_id',
        from_account: '$from.account_number', to_account: '$to.account_number',
        from_customer: '$from.customer_id',   to_customer: '$to.customer_id',
        amount: 1, created_at: 1 } },
    { $match: { from_account: { $ne: null }, to_account: { $ne: null } } },
    { $merge: { into: 'transfer_edge', whenMatched: 'replace', whenNotMatched: 'insert' } }
]).toArray();
print('edges built in ' + (Date.now() - mergeStart) + ' ms');
print('transfer_edge documents: ' + db.transfer_edge.countDocuments());
db.transfer_edge.createIndex({ from_account: 1 }, { name: 'ix_from' });
db.transfer_edge.createIndex({ to_account: 1 }, { name: 'ix_to' });
printjson(db.transfer_edge.findOne());

// -------------------------------------------------------------------
hr('M7  GRAPH TRAVERSAL - follow the money with $graphLookup');
// The fraud question a relational schema answers with a recursive CTE:
// starting from one account, which accounts did money reach within three
// hops? $graphLookup walks from_account -> to_account repeatedly.
const seed = db.transfer_edge.findOne();
const trail = db.transfer_edge.aggregate([
    { $match: { from_account: seed.from_account } },
    { $limit: 1 },
    { $graphLookup: {
        from: 'transfer_edge',
        startWith: '$to_account',
        connectFromField: 'to_account',
        connectToField: 'from_account',
        as: 'money_trail',
        maxDepth: 2,                       // 0-indexed: start + 2 = 3 hops
        depthField: 'hop',
        restrictSearchWithMatch: { amount: { $gt: Decimal128('500') } }
    } },
    { $project: {
        origin: '$from_account', first_hop: '$to_account',
        reached: { $size: '$money_trail' },
        trail: { $slice: [ { $map: { input: '$money_trail', as: 'm',
                   in: { hop: '$$m.hop', from: '$$m.from_account',
                         to: '$$m.to_account', amount: '$$m.amount' } } }, 8 ] } } }
]).toArray();
print('origin account   : ' + trail[0].origin);
print('first hop        : ' + trail[0].first_hop);
print('accounts reached within 3 hops: ' + trail[0].reached);
trail[0].trail.forEach(h => print('  hop ' + h.hop + '  ' + h.from + ' -> ' + h.to +
    '   NGN ' + h.amount.toString()));

// -------------------------------------------------------------------
hr('M8  SCHEMA VALIDATION - the writes the collection refuses');
// MongoDB accepts anything unless a validator says otherwise. These four
// attempts must all fail; the last must succeed.
const attempts = [
    ['V1 kyc_tier out of range (9)', () => db.customer_profile.insertOne(
        { _id: 'CUST-BAD-1', customer_id: 9999991, name: { first: 'Bad', last: 'Tier' },
          phone: '08111111111', kyc_tier: 9, status: 'ACTIVE', accounts: [] })],
    ['V2 balance as a double, not decimal', () => db.customer_profile.insertOne(
        { _id: 'CUST-BAD-2', customer_id: 9999992, name: { first: 'Bad', last: 'Money' },
          phone: '08111111112', kyc_tier: 2, status: 'ACTIVE',
          accounts: [{ account_number: '1234567890', balance: 1000.10, status: 'ACTIVE' }] })],
    ['V3 unknown status value', () => db.customer_profile.insertOne(
        { _id: 'CUST-BAD-3', customer_id: 9999993, name: { first: 'Bad', last: 'Status' },
          phone: '08111111113', kyc_tier: 1, status: 'ZOMBIE', accounts: [] })],
    ['V4 single-leg transaction (money from nowhere)', () => db.txn_event.insertOne(
        { _id: 'TXN-BAD-1', txn_type: 'TRANSFER', channel: 'USSD', status: 'SUCCESS',
          amount: Decimal128('5000.00'), created_at: new Date(),
          legs: [{ account_number: ACCT, direction: 'DR', amount: Decimal128('5000.00') }] })],
    ['V5 the same transaction with both legs (must SUCCEED)', () => db.txn_event.insertOne(
        { _id: 'TXN-GOOD-1', txn_type: 'TRANSFER', channel: 'USSD', status: 'SUCCESS',
          amount: Decimal128('5000.00'), created_at: new Date(),
          legs: [{ account_number: ACCT, direction: 'DR', amount: Decimal128('5000.00') },
                 { account_number: ACCT2, direction: 'CR', amount: Decimal128('5000.00') }] })]
];
attempts.forEach(([label, fn]) => {
    try { fn(); print('  ' + label + ' -> ACCEPTED'); }
    catch (e) { print('  ' + label + ' -> REJECTED: ' + (e.errmsg || e.message).slice(0, 90)); }
});
db.txn_event.deleteOne({ _id: 'TXN-GOOD-1' });   // clean up the accepted one

// -------------------------------------------------------------------
hr('M9  WHAT THE VALIDATOR CANNOT DO');
// The validator checks one document in isolation. It cannot express
// "debits must equal credits", because that is an arithmetic relationship
// BETWEEN the array elements. This document is internally inconsistent and
// is accepted without complaint.
try {
    db.txn_event.insertOne({
        _id: 'TXN-SKEW-1', txn_type: 'TRANSFER', channel: 'USSD', status: 'SUCCESS',
        amount: Decimal128('5000.00'), created_at: new Date(),
        legs: [{ account_number: ACCT, direction: 'DR', amount: Decimal128('5000.00') },
               { account_number: ACCT2, direction: 'CR', amount: Decimal128('4000.00') }]
    });
    print('  unbalanced document (DR 5000 vs CR 4000) -> ACCEPTED  <-- no equivalent of');
    print('  PostgreSQL trg_ledger_balanced exists here; the application must enforce it');
    const bad = db.txn_event.aggregate([
        { $match: { _id: 'TXN-SKEW-1' } },
        { $project: { dr: { $sum: { $map: { input: { $filter: { input: '$legs', as: 'l', cond: { $eq: ['$$l.direction', 'DR'] } } }, as: 'x', in: '$$x.amount' } } },
                      cr: { $sum: { $map: { input: { $filter: { input: '$legs', as: 'l', cond: { $eq: ['$$l.direction', 'CR'] } } }, as: 'x', in: '$$x.amount' } } } } }
    ]).toArray()[0];
    print('  detected only by querying for it afterwards: DR=' + bad.dr + ' CR=' + bad.cr);
} catch (e) { print('  unexpectedly rejected: ' + e.message); }
db.txn_event.deleteOne({ _id: 'TXN-SKEW-1' });

hr('COLLECTION STATISTICS');
['customer_profile', 'txn_event', 'transfer_edge'].forEach(c => {
    const s = db[c].stats();
    print('  ' + c.padEnd(18) + 'docs ' + String(db[c].countDocuments()).padStart(7) +
          '   data ' + (s.size / 1048576).toFixed(2) + ' MB' +
          '   indexes ' + (s.totalIndexSize / 1048576).toFixed(2) + ' MB' +
          '   avg doc ' + Math.round(s.avgObjSize) + ' B');
});
