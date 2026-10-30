#!/bin/zsh
# Bắn thông báo thử để xem kiểu Compact / Full trên notch.
# Chạy:  ./test-notifications.sh          (menu)
#        ./test-notifications.sh all      (chạy hết các case, cách nhau 10s)
#        ./test-notifications.sh 2        (chạy 1 case)

DOMAIN=theboringteam.boringnotch

notify() {  # notify <title> <subtitle> <body>
  local title=$1 subtitle=$2 body=$3
  local script="display notification \"${body//\"/\\\"}\""
  [[ -n $title ]] && script+=" with title \"${title//\"/\\\"}\""
  [[ -n $subtitle ]] && script+=" subtitle \"${subtitle//\"/\\\"}\""
  osascript -e "$script"
}

current() {
  local style scroll
  style=$(defaults read $DOMAIN notificationStyle 2>/dev/null || echo "compact (mặc định)")
  scroll=$(defaults read $DOMAIN notificationScrollLongMessages 2>/dev/null || echo "1 (mặc định)")
  echo "Style: $style | Chạy chữ: $scroll | Auto-expand: $(defaults read $DOMAIN notificationAutoExpand 2>/dev/null || echo 0)"
}

run_case() {
  case $1 in
    1) echo "→ Tin ngắn (không được chạy chữ)"
       notify "Minh Anh" "" "Ok bro 👍" ;;
    2) echo "→ Tin dài (phải chạy chữ nếu bật, hoặc cắt bằng … nếu tắt)"
       notify "Minh Anh" "" "Tối nay đi ăn lẩu không bro? 7h ở chỗ cũ nha, nhớ mang theo cái sạc giùm mình, mình quên ở nhà rồi" ;;
    3) echo "→ Có subtitle (dòng 2 = subtitle · nội dung)"
       notify "Minh Anh" "Nhóm Lẩu Thứ 6" "Ai đi thì thả tim nha, mình đặt bàn cho đủ người" ;;
    4) echo "→ Không có title (dòng 1 phải hiện tên app)"
       notify "" "" "Thông báo không có tiêu đề, kiểm tra dòng 1 hiện tên app" ;;
    5) echo "→ Tin rất dài + emoji (kiểm tra cuộn hết câu, mép mờ)"
       notify "Deploy Bot 🚀" "" "✅ Build #1234 passed • 🧪 412 tests • ⏱ 3m21s • 📦 boring-notch-custom.dmg đã upload lên server nội bộ, nhớ kiểm tra changelog trước khi gửi cho cả team nha 🙏" ;;
    6) echo "→ 3 tin liên tiếp. Rê chuột lên notch NGAY để giữ lại, sẽ thấy badge +N"
       notify "Minh Anh" "" "Tin 1: alo"
       sleep 1
       notify "Hoàng" "" "Tin 2: tới chưa bro, mọi người tới đủ rồi nè"
       sleep 1
       notify "Lan" "" "Tin 3: mình tới trễ 15 phút nhé" ;;
    *) echo "Không có case $1"; return 1 ;;
  esac
}

set_pref() {  # set_pref <key> <type> <value>
  defaults write $DOMAIN $1 -$2 $3
  echo "Đã đặt $1 = $3"
}

if [[ $1 == all ]]; then
  current
  for i in 1 2 3 4 5 6; do run_case $i; sleep 10; done
  exit 0
elif [[ -n $1 ]]; then
  run_case $1; exit $?
fi

while true; do
  echo
  current
  cat <<'MENU'
 1) Tin ngắn          2) Tin dài           3) Có subtitle
 4) Không có title    5) Rất dài + emoji   6) 3 tin liên tiếp (+N)
 a) Chạy hết 1→6 (cách nhau 10s)
 c) Style = Compact   f) Style = Full
 s) Bật chạy chữ      n) Tắt chạy chữ
 e) Bật auto-expand   x) Tắt auto-expand
 q) Thoát
MENU
  read "k?Chọn: "
  case $k in
    [1-6]) run_case $k ;;
    a) for i in 1 2 3 4 5 6; do run_case $i; sleep 10; done ;;
    c) set_pref notificationStyle string compact ;;
    f) set_pref notificationStyle string full ;;
    s) set_pref notificationScrollLongMessages bool true ;;
    n) set_pref notificationScrollLongMessages bool false ;;
    e) set_pref notificationAutoExpand bool true ;;
    x) set_pref notificationAutoExpand bool false ;;
    q) break ;;
  esac
done
