# Sentinel Lab - Linux Monitoring & Automated Backup

Hệ thống giám sát tài nguyên Linux và tự động sao lưu log từ Server A sang Server B thông qua SSH và Rsync, được xây dựng bằng Bash và systemd.

## 1. Tổng quan

Sentinel Lab được xây dựng nhằm giải quyết hai bài toán:

- **Resource Monitoring:** Theo dõi mức sử dụng CPU, RAM và Disk, ghi nhận kết quả và cảnh báo khi tài nguyên vượt ngưỡng cấu hình.
- **Automated Backup:** Sao lưu log từ máy giám sát sang máy chủ từ xa thông qua SSH/Rsync, có kiểm tra lỗi và ngăn nhiều tiến trình backup chạy đồng thời.

Hệ thống hoạt động theo mô hình hai máy chủ:

| Thành phần | Môi trường | Vai trò |
|---|---|---|
| Server A | WSL Ubuntu / Linux | Giám sát tài nguyên, ghi log và gửi backup |
| Server B | AWS EC2 Ubuntu | Nhận và lưu trữ các file backup |

Trong mô hình hiện tại, toàn bộ script giám sát và sao lưu được thực thi trên Server A. Server B đóng vai trò nhận dữ liệu, không cần cài đặt toàn bộ ứng dụng Sentinel Lab.

## 2. Kiến trúc hệ thống

```text
                     SERVER A - LINUX / WSL
                  +---------------------------+
                  |                           |
                  |  systemd                  |
                  |     |                     |
                  |     +-- Collector Timer   |
                  |     |       |             |
                  |     |       v             |
                  |     |  collect_metrics.sh |
                  |     |       |             |
                  |     |       v             |
                  |     |  CPU / RAM / Disk   |
                  |     |       |             |
                  |     |       v             |
                  |     |  all_log/           |
                  |     |                     |
                  |     +-- Backup Timer      |
                  |             |             |
                  |             v             |
                  |       backup_logs.sh      |
                  |             |             |
                  |       Validation + flock  |
                  |             |             |
                  +-------------|-------------+
                                |
                           SSH + Rsync
                                |
                                v
                     SERVER B - AWS EC2
                  +---------------------------+
                  |                           |
                  |   sentinel-backups/       |
                  |      metrics.log          |
                  |      sentinel_alert.log  |
                  |                           |
                  +---------------------------+
```

### Luồng giám sát

1. `sentinel-collector.timer` kích hoạt `sentinel-collector.service`.
2. Service thực thi `collect_metrics.sh`.
3. Script thu thập CPU, RAM và Disk.
4. Kết quả được ghi vào `metrics.log`.
5. Nếu tài nguyên đạt hoặc vượt ngưỡng, cảnh báo được ghi vào `sentinel_alert.log`.

### Luồng sao lưu

1. `sentinel-backup.timer` kích hoạt `sentinel-backup.service`.
2. Service thực thi `backup_logs.sh`.
3. Script kiểm tra cấu hình và sử dụng `flock` để ngăn backup chạy trùng.
4. Kiểm tra kết nối SSH tới Server B.
5. Tạo thư mục đích trên Server B nếu chưa tồn tại.
6. Sử dụng Rsync để đồng bộ log.
7. Ghi kết quả vào `backup_log/backup.log`.

## 3. Công nghệ sử dụng

| Công nghệ | Mục đích |
|---|---|
| Ubuntu Linux | Môi trường thực thi |
| Bash | Xây dựng script giám sát, backup và triển khai |
| systemd | Quản lý service và timer |
| OpenSSH | Kết nối và xác thực giữa hai server |
| Rsync | Đồng bộ dữ liệu qua SSH |
| flock | Ngăn các tiến trình backup thực thi đồng thời |
| APT | Quản lý dependency trên Ubuntu |
| AWS EC2 | Máy chủ nhận backup |
| Git / GitHub | Quản lý mã nguồn và tài liệu |

## 4. Cấu trúc dự án

```text
sentinel-lab/
├── config/
│   ├── .env.example
│   └── .env
│
├── scripts/
│   ├── collect_metrics.sh
│   └── backup_logs.sh
│
├── systemd/
│   ├── sentinel-collector.service.template
│   ├── sentinel-collector.timer
│   ├── sentinel-backup.service.template
│   └── sentinel-backup.timer
│
├── all_log/
│   ├── metrics.log
│   └── sentinel_alert.log
│
├── backup_log/
│   └── backup.log
│
├── setup.sh
├── install.sh
├── .gitignore
└── README.md
```

Các thư mục log và file log được tạo trong quá trình thực thi khi cần thiết.

File `.env` chứa cấu hình theo môi trường và không được đưa lên GitHub.

Các file `.service.template` được `install.sh` sử dụng để sinh systemd service với username và đường dẫn phù hợp với máy đang triển khai.

## 5. Chức năng chính

### 5.1. Giám sát CPU, RAM và Disk

Script `collect_metrics.sh` thu thập:

- **CPU:** Tính tỷ lệ sử dụng từ hai lần đọc `/proc/stat`.
- **RAM:** Tính tỷ lệ sử dụng dựa trên `MemTotal` và `MemAvailable` trong `/proc/meminfo`.
- **Disk:** Lấy tỷ lệ sử dụng filesystem gắn tại `/` thông qua `df -P`.

Các ngưỡng cảnh báo được thiết lập trong `config/.env`.

Ví dụ log:

```text
[2026-10-22 12:29:18] [OK] CPU=0% RAM=12% DISK=2%
```

Khi đạt hoặc vượt ngưỡng, trạng thái được chuyển thành `WARNING` và thông tin cảnh báo được ghi riêng.

### 5.2. Sao lưu log qua SSH và Rsync

Script `backup_logs.sh` hỗ trợ:

- Kiểm tra các biến cấu hình bắt buộc.
- Kiểm tra thư mục nguồn và SSH private key.
- Kiểm tra định dạng SSH port và địa chỉ máy chủ đích.
- Xác thực SSH không tương tác bằng private key.
- Tạo thư mục backup từ xa.
- Sao lưu bằng Rsync qua SSH.
- Ghi log thành công hoặc thất bại.

Rsync giúp đồng bộ dữ liệu hiệu quả bằng cách chỉ truyền những phần dữ liệu cần cập nhật, tùy thuộc đặc điểm file và tùy chọn sử dụng.

### 5.3. Chống chạy trùng bằng flock

Script sử dụng Linux file locking để tránh nhiều lượt backup chạy cùng lúc.

```bash
LOCK_FILE="/tmp/sentinel-backup.lock"

exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    log_message "WARNING" "Another backup is already running"
    exit 0
fi
```

Nếu một tiến trình đang giữ khóa, tiến trình mới sẽ bỏ qua lượt backup.

Cơ chế này giúp hạn chế việc hai tiến trình Rsync đồng thời thao tác trên cùng thư mục đích.

### 5.4. Tự động chạy bằng systemd

Hệ thống sử dụng hai cặp unit:

| Timer | Service | Lịch |
|---|---|---|
| `sentinel-collector.timer` | `sentinel-collector.service` | Mỗi 5 phút |
| `sentinel-backup.timer` | `sentinel-backup.service` | Mỗi 15 phút |

Collector timer được bật tự động bởi `install.sh`.

Backup timer được bật thủ công khi Server B đã sẵn sàng.

### 5.5. Tự động chuẩn bị và triển khai

`setup.sh` thực hiện:

- Kiểm tra dependency.
- Hỗ trợ cài đặt package còn thiếu thông qua `--install-deps`.
- Khởi tạo `config/.env` từ `.env.example` nếu chưa tồn tại.
- Không ghi đè cấu hình `.env` đã có.

`install.sh` thực hiện:

- Kiểm tra quyền quản trị.
- Xác định username và thư mục dự án.
- Kiểm tra các file cấu hình cần thiết.
- Sinh service từ template.
- Kiểm tra systemd unit.
- Cài đặt unit vào `/etc/systemd/system/`.
- Reload systemd.
- Bật và xác minh collector timer.

## 6. Yêu cầu môi trường

### Server A

- Ubuntu Linux có systemd hoạt động.
- Bash và các công cụ Linux thông dụng.
- OpenSSH Client.
- Rsync.
- Quyền sudo để cài đặt package và systemd unit.
- SSH private key được cấp quyền truy cập Server B.

Có thể sử dụng WSL Ubuntu với điều kiện systemd đã được bật.

### Server B

- Linux server có SSH server hoạt động.
- Tài khoản nhận backup.
- Public key tương ứng với private key của Server A đã được cấp quyền đăng nhập.
- Quyền ghi vào thư mục đích.
- Firewall hoặc AWS Security Group cho phép kết nối SSH từ Server A.

## 7. Hướng dẫn cài đặt

### Bước 1 - Clone repository

```bash
git clone https://github.com/jasonnismee/sentinel-lab.git

cd sentinel-lab
```

### Bước 2 - Chuẩn bị dependency

Kiểm tra các công cụ cần thiết:

```bash
bash setup.sh
```

Nếu thiếu dependency:

```bash
bash setup.sh --install-deps
```

Tùy chọn `--install-deps` cho phép cài các package còn thiếu bằng APT.

Không chạy `setup.sh` bằng root. Script chỉ sử dụng sudo khi cần cài package.

### Bước 3 - Cấu hình môi trường

Nếu chưa có `.env`, `setup.sh` sẽ khởi tạo file từ `.env.example`.

Mở file:

```bash
nano config/.env
```

Các biến cấu hình:

| Biến | Ý nghĩa |
|---|---|
| `THRESHOLD_CPU` | Ngưỡng cảnh báo CPU (%) |
| `THRESHOLD_MEM` | Ngưỡng cảnh báo RAM (%) |
| `THRESHOLD_DISK` | Ngưỡng cảnh báo Disk (%) |
| `APP_LOG_DIR` | Thư mục log monitoring |
| `BACKUP_LOG_DIR` | Thư mục ghi log quá trình backup |
| `SRC_DIR` | Thư mục dữ liệu cần sao lưu |
| `DEST_DIR` | Thư mục nhận backup trên Server B |
| `DEST_SERVER` | Địa chỉ SSH theo dạng `user@host` |
| `PORT` | Cổng SSH |
| `SSH_KEY` | Đường dẫn SSH private key |

Ví dụ minh họa:

```bash
THRESHOLD_CPU=90
THRESHOLD_MEM=80
THRESHOLD_DISK=80

APP_LOG_DIR="$PROJECT_DIR/all_log"
BACKUP_LOG_DIR="$PROJECT_DIR/backup_log"
SRC_DIR="$PROJECT_DIR/all_log/"

DEST_SERVER=ubuntu@YOUR_EC2_PUBLIC_IP
DEST_DIR=/home/ubuntu/sentinel-backups/
PORT=22
SSH_KEY=/home/your-user/.ssh/sentinel-backup-key.pem
```

Thay `YOUR_EC2_PUBLIC_IP` và đường dẫn SSH key bằng thông tin thực tế.

Biến `PROJECT_DIR` được các script xác định trước khi đọc `.env`, giúp đường dẫn log thay đổi theo vị trí của repository.

**Lưu ý:** File `.env` được nạp bằng Bash `source`, vì vậy chỉ sử dụng file cấu hình đáng tin cậy.

### Bước 4 - Chuẩn bị SSH

Trên Server A, cần có SSH private key và public key tương ứng đã được cấp quyền đăng nhập trên Server B.

Nếu chưa có SSH key, có thể tạo:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/sentinel-backup-key
```

Chỉ thực hiện khi đường dẫn key chưa tồn tại, tránh ghi đè key đang sử dụng.

Thiết lập quyền private key:

```bash
chmod 600 ~/.ssh/sentinel-backup-key
```

Cài public key vào `~/.ssh/authorized_keys` của tài khoản nhận backup trên Server B bằng phương thức được quản trị viên cho phép.

Kiểm tra SSH:

```bash
ssh -i ~/.ssh/sentinel-backup-key \
    -o BatchMode=yes \
    -p 22 \
    ubuntu@YOUR_EC2_PUBLIC_IP
```

Cần xác minh host key của Server B trước khi tin cậy kết nối.

Không đưa private key lên GitHub.

### Bước 5 - Cài đặt systemd

Sau khi chuẩn bị `.env`:

```bash
sudo bash install.sh
```

Installer sẽ sinh service từ template và cài các systemd unit.

Kiểm tra:

```bash
systemctl status sentinel-collector.timer

systemctl list-timers --all | grep sentinel
```

Backup timer không được tự động bật bởi installer.

### Bước 6 - Bật backup timer

Khi Server B đang chạy và cấu hình SSH đã sẵn sàng:

```bash
sudo systemctl enable --now sentinel-backup.timer
```

Kiểm tra lịch:

```bash
systemctl list-timers --all | grep sentinel
```

Khi không sử dụng EC2:

```bash
sudo systemctl disable --now sentinel-backup.timer
```

Việc này tránh các lượt backup tự động khi máy chủ đích đã tắt.

## 8. Chạy và kiểm thử thủ công

### Kiểm thử monitoring

```bash
bash scripts/collect_metrics.sh
```

Kiểm tra log:

```bash
tail -n 10 all_log/metrics.log
```

Theo dõi liên tục:

```bash
tail -f all_log/metrics.log
```

### Kiểm thử backup

Khi Server B sẵn sàng:

```bash
bash scripts/backup_logs.sh
```

Kiểm tra log:

```bash
tail -n 10 backup_log/backup.log
```

### Kiểm thử qua systemd

Chạy collector một lần:

```bash
sudo systemctl start sentinel-collector.service
```

Kiểm tra:

```bash
systemctl status sentinel-collector.service
```

Chạy backup một lần:

```bash
sudo systemctl start sentinel-backup.service
```

Kiểm tra nhật ký:

```bash
journalctl -u sentinel-backup.service -n 30 --no-pager
```

