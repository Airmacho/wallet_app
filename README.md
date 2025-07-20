# WalletApp 💰

A simple, centralized wallet backend service built with Ruby, PostgreSQL, and Redis.  
Supports core operations: deposit, withdraw, transfer, view balances, and transaction history.

---

## 🛠️ Tech Stack

- **Language:** Ruby 3.2.2
- **Framework:** Rails 7.1.5 (API-only)
- **Database:** PostgreSQL
- **In-memory Store:** Redis
- **Currency Handling:** [Money gem](https://github.com/RubyMoney/money)
- **Testing**: RSpec, SimpleCov (94% test coverage)

---

## 🚀 Features

- Deposit and withdraw money from a user's wallet
- Transfer funds between users (with currency conversion)
- View current wallet balance and transaction history
- Full idempotency support via Redis
- Pessimistic locking and atomic DB transactions
- Immutable, auditable transaction records

---

## 📊 Data Modeling

The system is structured around three core tables: `users`, `wallets`, and `transactions`.

### 1. Users

| Field     | Type   | Description                            |
|-----------|--------|----------------------------------------|
| `id`      | bigint | Primary key                            |
| `email`   | string | Unique identifier for each user        |
| `api_key` | string | Simple hard-coded token for API access |

- Each user **owns exactly one wallet**.
- Authentication is intentionally lightweight, using a static `api_key` provided in the request header, as auth is not the primary focus of this app.

### 2. Wallets

| Field           | Type   | Description                                        |
|-----------------|--------|----------------------------------------------------|
| `id`            | bigint | Primary key                                        |
| `user_id`       | bigint | Foreign key to `users` (1:1)          |
| `balance_cents` | bigint | Stored in bigint to avoid floating point precision issues; consistent with Stripe/Shopify recommendations.     |
| `currency`      | string | ISO currency code (e.g., `USD`)                    |

- Represents a user’s wallet and available balance.
- All balance modifications are atomic (DB transactions).

### 3. Transactions

| Field              | Type     | Description                                                         |
|--------------------|----------|---------------------------------------------------------------------|
| `id`               | bigint   | Primary key                                                         |
| `wallet_id`        | bigint   | Foreign key to the impacted wallet                                  |
| `transaction_type` | enum     | `deposit`, `withdraw`, `transfer_in`, `transfer_out`                |
| `amount_cents`     | bigint   | Always stored as a **positive** value in cents                      |
| `currency`         | string   | Derived from the wallet(s) involved                                 |
| `status`           | string   | `pending`, `succeeded`, `failed`                                    |
| `idempotency_key`  | string   | Used to deduplicate/group related operations                        |
| `failed_reason`    | string   | Optional (e.g., `failed_reason` if status is `failed`)              |
| `timestamps`       | datetime | Standard created/updated audit timestamps                           |

- **All fund activities** (including failed attempts) are persisted.
- **Deposits & Withdrawals:** One record each.
- **Transfers:** Two records:
  - `transfer_out` (sender’s wallet)
  - `transfer_in` (recipient’s wallet)
  - Both share the same `idempotency_key`.

---

## 🧩 Architecture Trade-offs

### Idempotency Check

Suppose a user clicks "Transfer $100" twice due to a slow network:

```http
POST /transfer {"amount": 100}  # First request
POST /transfer {"amount": 100}  # Duplicate - should be ignored
```

- **Without idempotency:** User loses $200 (both requests processed)
- **With proper idempotency:** User loses $100, second request returns cached result

Duplicate requests are handled safely using Redis-based idempotency control:

| State                        | Meaning                                 | TTL         |
|------------------------------|-----------------------------------------|-------------|
| `"PROCESSING"`               | Request in progress, blocks duplicates  | ~1 minute   |
| serialized transaction object| Completed result for reuse              | ~1 hour     |

Single Redis key lifecycle:
- First request: sets key to "PROCESSING"
- Upon success: replaces with serialized result
- Second request: sees cached result and returns immediately

### Transaction Handling
- All write operations(deposit/withdraw/transfer) are performed inside a database transaction.
- For transfers, both wallets are locked in a `consistent order` to prevent circular deadlocks.
- Each operation follows a pattern: create a transaction with status `pending`, execute business logic, then mark as `completed` or `failed` with a reason. This provides a full audit trail and ensures atomicity and consistency.

### Concurrency Safety
- SELECT ... FOR UPDATE ensures row-level pessimistic locking
- Wallets are always locked in consistent order to prevent deadlocks
- Funds are modified only within transactions for atomicity

### Why not apply event sourcing?

The current `transaction` model design provides core Event Sourcing benefits:
- Immutable records (transactions never updated after completion)
- Failed operations are recorded with failure reasons in failed_reason field
- Complete operation timeline through transaction history
- Consistent pattern: all services (deposit/withdraw/transfer) record attempts,
- Audit trail for compliance and debugging

Full Event Sourcing not implemented because:
 - ES best practice uses specialized stores (EventStore, Kafka)
 - PostgreSQL not optimized for append-only event streams
 - Current requirements satisfied without full ES overhead

---

## 📚 API Endpoints

All API requests require the user's `api_key` in the headers:

```
X-User-API-Key: api_key_value
```

- You can find your `api_key` by running `rails c` and querying the User model.
- For wallet operations (deposit, withdraw, and transfer), an `Idempotency-Key` is required. In typical client-server setups, the client receives this key from the server when the page loads. Since this project is API-only, you can generate and use any unique value as the `Idempotency-Key`.

### Deposit Money

```bash
POST /v1/deposits

curl -X POST http://localhost:3000/v1/deposits \
  -H "X-User-API-Key: your_key" \
  -H "Idempotency-Key: deposit-001" \
  -H "Content-Type: application/json" \
  -d '{"deposit": {"amount_cents": 10000}}'
```

### Withdraw Money

```bash
POST /v1/withdrawals

curl -X POST http://localhost:3000/v1/withdrawals \
  -H "X-User-API-Key: your_key" \
  -H "Idempotency-Key: withdrawal-001" \
  -H "Content-Type: application/json" \
  -d '{"withdrawal": {"amount_cents": 3000}}'
```

### Transfer Money

```bash
POST /v1/transfers

curl -X POST http://localhost:3000/v1/transfers \
  -H "X-User-API-Key: your_key" \
  -H "Idempotency-Key: transfer-001" \
  -H "Content-Type: application/json" \
  -d '{"transfer": {"to_email": "user2@example.com", "amount_cents": 4000}}'
```

### Get Wallet Balance

```bash
GET /v1/me/wallet

curl -H "X-User-API-Key: your_key" http://localhost:3000/v1/me/wallet
```

### Get Transaction History

```bash
GET /v1/me/transactions

curl -H "X-User-API-Key: your_key" http://localhost:3000/v1/me/transactions
```

---

## 🚧 Improvements & Future Work

### Currency Exchange
- Replace hardcoded rates with live provider (e.g., OpenExchangeRates)
- Add background sync of exchange rates

### Authentication & Security
- Upgrade API auth from static keys to JWT or OAuth2
- Add rate limiting and abuse protection
- Implement proper session management

### Observability
- Structured logs for key operations
- Prometheus metrics for API performance, error rates, etc.

### Caching
- Cache read-heavy endpoints like balances and histories
- Invalidate cache safely after wallet updates

### API Improvements
- Pagination for transaction history
- Advanced filtering and search
- Webhook notifications for transaction events

### Potential Business Logic
- Transaction limits (e.g., daily cap)
- Transaction fees calculation
- Multi-currency wallet support per user

---

## 📦 Setup Instructions

### Prerequisites

- Ruby 3.2.2
- PostgreSQL
- Redis

### Local Setup

```bash
git clone https://github.com/Airmacho/wallet_app.git
cd wallet_app
bundle install
rails rake db:drop db:create db:migrate db:seed
```

### Running Tests
To run the full test suite and see coverage:

```bash
bundle exec rspec
```

### Reviewer Notes

To highlight key design decisions:
```bash
bundle exec rails notes --annotations KEY_POINT
```

---

## ⏱️ Time Breakdown
- Planning & System Design: 1h
- Core Implementation: 2h
- Testing Cases: 2h
- Documentation & Cleanup: 2h

**Total**: ~6 hours

---
