#!/bin/bash
# F5 VPN split tunneling 자동 로그인 설치 스크립트
#
# 설치 항목:
#   1. openconnect (F5 VPN 클라이언트)
#   2. vpn-slice (스플릿 터널링)
#   3. Python 패키지 (Playwright, requests, python-dotenv)
#   4. Chromium 브라우저 (Playwright용)
#   5. Gmail OAuth 인증 (OTP 이메일 자동 읽기)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --------------------------------------------------
# 1. 시스템 패키지 설치
# --------------------------------------------------
info "시스템 패키지 확인 중..."

if ! command -v brew &>/dev/null; then
    error "Homebrew가 설치되어 있지 않습니다. https://brew.sh 에서 설치해 주세요."
fi

if ! command -v openconnect &>/dev/null; then
    info "openconnect 설치 중..."
    brew install openconnect
else
    info "openconnect 이미 설치됨: $(openconnect --version 2>&1 | head -1)"
fi

# --------------------------------------------------
# 2. Python 패키지 설치
# --------------------------------------------------
info "Python 패키지 확인 중..."

pip_install_if_missing() {
    if ! python3 -c "import $1" 2>/dev/null; then
        info "$2 설치 중..."
        pip3 install "$2"
    else
        info "$2 이미 설치됨"
    fi
}

pip_install_if_missing "vpn_slice" "vpn-slice"
pip_install_if_missing "playwright" "playwright"
pip_install_if_missing "requests" "requests"
pip_install_if_missing "dotenv" "python-dotenv"

# --------------------------------------------------
# 3. Playwright 브라우저 설치
# --------------------------------------------------
info "Playwright Chromium 브라우저 설치 중..."
python3 -m playwright install chromium

# --------------------------------------------------
# 4. .env 파일 설정
# --------------------------------------------------
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    info ".env 파일 생성 중..."
    read -rp "VPN 사용자 이름: " vpn_user
    read -rsp "VPN 비밀번호: " vpn_pass
    echo
    cat > "$ENV_FILE" <<EOF
VPN_USERNAME=$vpn_user
VPN_PASSWORD=$vpn_pass
EOF
    chmod 600 "$ENV_FILE"
    info ".env 파일 생성 완료 (권한: 600)"
else
    info ".env 파일 이미 존재"
fi

# --------------------------------------------------
# 5. Gmail OAuth 설정
# --------------------------------------------------
GMAIL_MCP_DIR="$HOME/.gmail-mcp"
mkdir -p "$GMAIL_MCP_DIR"

if [ -f "$GMAIL_MCP_DIR/credentials.json" ]; then
    info "Gmail OAuth 인증 이미 완료됨"
else
    info "Gmail OAuth 설정이 필요합니다."
    echo ""
    echo "============================================"
    echo " Gmail API OAuth 설정 가이드"
    echo "============================================"
    echo ""
    echo "1. Google Cloud Console 접속:"
    echo "   https://console.cloud.google.com/"
    echo ""
    echo "2. 새 프로젝트 생성 또는 기존 프로젝트 선택"
    echo ""
    echo "3. Gmail API 활성화:"
    echo "   APIs & Services > Library > 'Gmail API' 검색 > 활성화"
    echo ""
    echo "4. OAuth 동의 화면 설정:"
    echo "   APIs & Services > OAuth consent screen"
    echo "   - External 선택"
    echo "   - 앱 이름, 이메일 입력"
    echo "   - 테스트 사용자에 본인 Gmail 주소 추가"
    echo ""
    echo "5. OAuth 클라이언트 ID 생성:"
    echo "   APIs & Services > Credentials > Create Credentials > OAuth client ID"
    echo "   - 애플리케이션 유형: '웹 애플리케이션'"
    echo "   - 승인된 리디렉션 URI: http://localhost:3000/oauth2callback"
    echo "   - JSON 다운로드"
    echo ""
    echo "============================================"
    echo ""
    read -rp "다운로드한 OAuth JSON 파일 경로를 입력하세요: " oauth_json_path

    if [ ! -f "$oauth_json_path" ]; then
        error "파일을 찾을 수 없습니다: $oauth_json_path"
    fi

    cp "$oauth_json_path" "$GMAIL_MCP_DIR/gcp-oauth.keys.json"
    info "OAuth 키 복사 완료"

    info "Gmail 인증 시작 (브라우저가 열립니다)..."
    npx @gongrzhe/server-gmail-autoauth-mcp auth

    if [ -f "$GMAIL_MCP_DIR/credentials.json" ]; then
        info "Gmail OAuth 인증 완료!"
    else
        error "Gmail 인증에 실패했습니다. 위 가이드를 다시 확인해 주세요."
    fi
fi

# --------------------------------------------------
# 완료
# --------------------------------------------------
echo ""
echo "============================================"
echo -e " ${GREEN}설치 완료!${NC}"
echo "============================================"
echo ""
echo " 사용법:"
echo ""
echo "   # 자동 로그인 + VPN 연결 (권장)"
echo "   python3 $SCRIPT_DIR/vpn-auto-login.py"
echo ""
echo "   # 수동 쿠키 방식"
echo "   sudo $SCRIPT_DIR/vpn-connect.sh <MRHSession 쿠키값>"
echo ""
echo "   # 헤드리스 모드 (브라우저 창 없이)"
echo "   python3 $SCRIPT_DIR/vpn-auto-login.py --headless"
echo ""
echo "============================================"
