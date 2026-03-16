# Cheatsheet MySQL Internals

## Mental model
- `mysqld` = process server
- SQL layer = parser + optimizer + executor
- storage engine = nơi dữ liệu thật sự được lưu/truy cập
- handler API = cây cầu giữa SQL layer và engine

## Storage
- buffer pool = page cache trong RAM
- page = đơn vị I/O cơ bản
- clustered index = cây primary key giữ luôn row data
- secondary index = key -> primary key
- bookmark lookup = tra secondary index rồi tra clustered index

## Concurrency
- MVCC = snapshot read mà trong nhiều trường hợp không chặn write
- undo log = version cũ + hỗ trợ rollback
- read view = luật nhìn thấy dữ liệu cho snapshot read
- gap/next-key locks = ngăn phantom trong ngữ nghĩa repeatable read
- deadlock = chờ vòng tròn; engine sẽ chọn một nạn nhân

## Durability
- WAL = ghi log trước, data page sau
- redo log = crash recovery cho các thay đổi đã commit
- LSN = vị trí trong luồng redo
- checkpoint = mốc mà tới đó dirty pages đã được flush an toàn
- doublewrite = bảo vệ khỏi torn-page

## Optimizer / performance
- optimizer = bộ chọn plan dựa trên cost
- EXPLAIN = plan ước lượng
- EXPLAIN ANALYZE = hành vi thực thi thực tế
- covering index = mọi cột cần thiết đều đã nằm trong index
- sargable predicate = predicate mà optimizer có thể tận dụng index hiệu quả

## Scale / ops
- redo log != binlog
- redo log = crash recovery cục bộ
- binlog = lan truyền thay đổi / replication / PITR
- GTID = định danh transaction toàn cục cho việc định vị replication
- replication != backup

## Chuỗi một dòng
```text
storage -> concurrency -> durability -> optimizer -> tuning -> scale/ops
```
