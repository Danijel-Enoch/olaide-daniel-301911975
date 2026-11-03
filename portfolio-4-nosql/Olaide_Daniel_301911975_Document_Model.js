// =====================================================================
// MIT 8103 Advanced Database Systems - Portfolio 4
// Student : Olaide Daniel (301911975)
// File    : MongoDB document model - collections, validators, indexes
// Run     : mongosh hdmb --quiet --file Olaide_Daniel_301911975_Document_Model.js
// =====================================================================
// Design rule applied throughout: embed what is read together and bounded,
// reference what is unbounded or shared. The 16MB BSON document limit is a
// hard design constraint, not a footnote - it is why recent_activity holds
// ten postings and the full history lives in txn_event.
// =====================================================================
const db = db.getSiblingDB('hdmb');

print('=== dropping any previous model ===');
['customer_profile', 'txn_event', 'transfer_edge'].forEach(c => {
    if (db.getCollectionNames().includes(c)) { db[c].drop(); print('  dropped ' + c); }
});

// ---------------------------------------------------------------------
// 1. customer_profile - the mobile home screen as a single document
// ---------------------------------------------------------------------
// MongoDB is schema-less by default. That is a liability for a bank, so a
// $jsonSchema validator is attached explicitly. Unlike a relational CHECK,
// this is opt-in and lives in the collection options rather than being
// unavoidable - a difference analysed in the README.
db.createCollection('customer_profile', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['_id', 'customer_id', 'name', 'phone', 'kyc_tier', 'status', 'accounts'],
            properties: {
                customer_id: { bsonType: 'int', minimum: 1 },
                bvn:         { bsonType: 'string', pattern: '^[0-9]{11}$' },
                phone:       { bsonType: 'string', pattern: '^[0-9]{11}$' },
                kyc_tier:    { bsonType: 'int', minimum: 1, maximum: 3 },
                status:      { enum: ['ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED'] },
                name: {
                    bsonType: 'object',
                    required: ['first', 'last'],
                    properties: { first: { bsonType: 'string' }, last: { bsonType: 'string' } }
                },
                accounts: {
                    bsonType: 'array',
                    items: {
                        bsonType: 'object',
                        required: ['account_number', 'balance', 'status'],
                        properties: {
                            account_number: { bsonType: 'string', pattern: '^[0-9]{10}$' },
                            // decimal, NOT double: a double cannot hold 0.10 exactly
                            balance:  { bsonType: 'decimal' },
                            status:   { enum: ['ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED'] },
                            currency: { bsonType: 'string', minLength: 3, maxLength: 3 }
                        }
                    }
                },
                recent_activity: {
                    bsonType: 'array',
                    maxItems: 10,          // the bound is part of the contract
                    items: {
                        bsonType: 'object',
                        required: ['txn_ref', 'direction', 'amount', 'ts'],
                        properties: {
                            direction: { enum: ['DR', 'CR'] },
                            amount:    { bsonType: 'decimal' },
                            ts:        { bsonType: 'date' }
                        }
                    }
                }
            }
        }
    },
    validationLevel: 'strict',
    validationAction: 'error'
});
print('=== created customer_profile with $jsonSchema validator ===');

// ---------------------------------------------------------------------
// 2. txn_event - append-only transaction events, journal legs embedded
// ---------------------------------------------------------------------
db.createCollection('txn_event', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['_id', 'txn_type', 'channel', 'status', 'amount', 'created_at', 'legs'],
            properties: {
                txn_type: { enum: ['TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'FEE', 'LOAN_DISB', 'LOAN_REPAY'] },
                channel:  { enum: ['USSD', 'MOBILE', 'WEB', 'POS', 'BRANCH', 'ATM'] },
                status:   { enum: ['PENDING', 'SUCCESS', 'FAILED', 'REVERSED'] },
                amount:   { bsonType: 'decimal' },
                created_at: { bsonType: 'date' },
                legs: {
                    bsonType: 'array',
                    minItems: 2,           // double entry, expressed as a cardinality
                    items: {
                        bsonType: 'object',
                        required: ['account_number', 'direction', 'amount'],
                        properties: {
                            direction: { enum: ['DR', 'CR'] },
                            amount:    { bsonType: 'decimal' }
                        }
                    }
                }
            }
        }
    },
    validationLevel: 'strict',
    validationAction: 'error'
});
print('=== created txn_event with $jsonSchema validator ===');

// ---------------------------------------------------------------------
// 3. Indexes - each one named for the query it serves
// ---------------------------------------------------------------------
db.customer_profile.createIndex({ customer_id: 1 }, { unique: true, name: 'uq_customer_id' });
db.customer_profile.createIndex({ phone: 1 }, { unique: true, name: 'uq_phone' });
db.customer_profile.createIndex({ bvn: 1 }, { unique: true, sparse: true, name: 'uq_bvn' });
// a multikey index: it indexes every element of the embedded accounts array,
// so "who owns account 0000000013" is a seek rather than a collection scan
db.customer_profile.createIndex({ 'accounts.account_number': 1 }, { name: 'ix_account_number' });
db.customer_profile.createIndex({ 'branch.code': 1, status: 1 }, { name: 'ix_branch_status' });
db.customer_profile.createIndex({ 'name.last': 1, 'name.first': 1 }, { name: 'ix_name' });

// compound, most selective field first, timestamp descending to match the sort
db.txn_event.createIndex({ 'legs.account_number': 1, created_at: -1 }, { name: 'ix_leg_account_time' });
db.txn_event.createIndex({ channel: 1, status: 1, created_at: -1 }, { name: 'ix_channel_status_time' });
db.txn_event.createIndex({ created_at: -1 }, { name: 'ix_created_at' });
db.txn_event.createIndex({ txn_type: 1, created_at: -1 }, { name: 'ix_type_time' });

print('=== indexes created ===');
printjson(db.customer_profile.getIndexes().map(i => i.name));
printjson(db.txn_event.getIndexes().map(i => i.name));
