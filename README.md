# vpn-bypass

F5 BIG-IP VPN의 스플릿 터널링 + 자동 로그인 도구 (macOS)

지정한 서브넷만 VPN을 통해 라우팅하고, 나머지 트래픽은 직접 연결을 유지합니다.
이메일 OTP 인증까지 완전 자동화하여, 명령어 한 줄로 VPN에 연결할 수 있습니다.

## 문제

F5 BIG-IP Edge Client는 **풀 터널**을 강제합니다 — 모든 트래픽이 VPN을 통과합니다.
클라이언트가 스플릿 터널링을 적극적으로 차단하기 때문에:

- 수동으로 변경한 라우팅을 실시간으로 되돌림
- `f5vpnhelper` 데몬이 라우팅 테이블 아래 수준에서 패킷을 가로챔

결과적으로 특정 호스트에만 VPN이 필요한 경우에도 인터넷이 매우 느려집니다.

## 해결 방법

F5 클라이언트를 [`openconnect`](https://www.infradead.org/openconnect/) (F5 프로토콜 지원) + [`vpn-slice`](https://github.com/dlenski/vpn-slice) (스플릿 터널링)로 대체합니다.

추가로 [Playwright](https://playwright.dev/)와 [Gmail API](https://developers.google.com/gmail/api)를 사용하여 브라우저 로그인과 이메일 OTP 인증을 자동화합니다.

### 자동화 흐름

```
vpn-auto-login.py 실행
  → Playwright가 VPN 포털 로그인 페이지를 열고 자격 증명 입력
  → 이메일 OTP 인증 선택 후 제출
  → Gmail API로 OTP 이메일을 폴링하여 인증 코드 추출
  → OTP 입력 후 제출
  → MRHSession 쿠키 추출
  → openconnect + vpn-slice로 스플릿 터널 VPN 연결
```

## 설치

### 빠른 설치

```bash
git clone https://github.com/yourusername/vpn-bypass.git
cd vpn-bypass
./install.sh
```

설치 스크립트가 다음을 자동으로 처리합니다:
1. `openconnect` 설치 (Homebrew)
2. Python 패키지 설치 (`vpn-slice`, `playwright`, `requests`, `python-dotenv`)
3. Playwright Chromium 브라우저 설치
4. `.env` 파일 생성 (VPN 자격 증명)
5. Gmail OAuth 인증 설정

### 수동 설치

#### 1. 시스템 패키지

```bash
brew install openconnect
pip install vpn-slice playwright requests python-dotenv
python3 -m playwright install chromium
```

#### 2. VPN 자격 증명 설정

프로젝트 루트에 `.env` 파일을 생성합니다:

```bash
VPN_USERNAME=사용자이름
VPN_PASSWORD=비밀번호
```

```bash
chmod 600 .env  # 권한 제한 권장
```

#### 3. Gmail API 설정 (자동 OTP 인증용)

OTP 이메일을 자동으로 읽기 위해 Gmail API OAuth 인증이 필요합니다.

**Google Cloud 설정:**

1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. 새 프로젝트 생성 (또는 기존 프로젝트 선택)
3. **Gmail API 활성화:**
   - APIs & Services → Library → "Gmail API" 검색 → 활성화
4. **OAuth 동의 화면 설정:**
   - APIs & Services → OAuth consent screen
   - "External" 선택
   - 앱 이름, 사용자 지원 이메일, 개발자 이메일 입력
   - 테스트 사용자에 본인 Gmail 주소 추가
5. **OAuth 클라이언트 ID 생성:**
   - APIs & Services → Credentials → Create Credentials → OAuth client ID
   - 애플리케이션 유형: **웹 애플리케이션**
   - 승인된 리디렉션 URI에 `http://localhost:3000/oauth2callback` 추가
   - JSON 파일 다운로드

**인증 실행:**

```bash
mkdir -p ~/.gmail-mcp
cp 다운로드한파일.json ~/.gmail-mcp/gcp-oauth.keys.json
npx @gongrzhe/server-gmail-autoauth-mcp auth
```

브라우저가 열리면 Google 계정으로 로그인하여 권한을 승인합니다.
인증이 완료되면 `~/.gmail-mcp/credentials.json`이 생성됩니다.

## 사용법

### 자동 로그인 (권장)

```bash
# 기본 (헤드리스 모드)
python3 vpn-auto-login.py

# 브라우저 창 표시 (디버깅용)
python3 vpn-auto-login.py --no-headless
```

스크립트가 자동으로:
1. Gmail API 액세스 토큰 획득
2. VPN 포털 로그인 페이지 열기
3. 자격 증명 입력 및 이메일 OTP 인증 선택
4. Gmail에서 OTP 코드 수신 대기 (최대 2분)
5. OTP 입력 및 제출
6. `MRHSession` 쿠키 추출
7. `openconnect + vpn-slice`로 VPN 연결

### 수동 쿠키 방식

자동 로그인 없이 직접 쿠키를 추출하여 연결할 수도 있습니다.

#### 1. 브라우저에서 인증

VPN 포털(예: `https://vpn.postech.ac.kr/`)에 로그인하고 2FA를 완료합니다.

#### 2. 세션 쿠키 복사

로그인 후 `MRHSession` 쿠키 값을 복사합니다:

**방법 A — 북마클릿 (권장)**

브라우저 북마크에 아래 URL을 등록합니다:

```
javascript:void(navigator.clipboard.writeText(document.cookie.split(';').map(c=>c.trim()).find(c=>c.startsWith('MRHSession=')).split('=')[1]).then(()=>alert('MRHSession copied!')))
```

로그인 후 클릭하면 쿠키가 클립보드에 복사됩니다.

**방법 B — 개발자 도구**

1. 개발자 도구 열기 (`F12` 또는 `Cmd+Option+I`)
2. **Application → Cookies → VPN 도메인**
3. `MRHSession` 값 복사

#### 3. 연결

```bash
sudo ./vpn-connect.sh <MRHSession 값>

# macOS 클립보드 사용:
sudo ./vpn-connect.sh $(pbpaste)
```

### 연결 확인

다른 터미널에서:

```bash
# VPN을 통해 라우팅되어야 함
ssh your-server

# 직접 연결 (VPN 미경유) — 빠른 속도 확인
ping 8.8.8.8
curl ifconfig.me
```

### 연결 해제

`vpn-connect.sh`가 실행 중인 터미널에서 `Ctrl+C`를 누릅니다.

## 설정

환경 변수로 설정을 변경할 수 있습니다:

```bash
# 다른 F5 서버에 연결
VPN_SERVER="https://vpn.example.com/" python3 vpn-auto-login.py

# 다른 서브넷을 VPN으로 라우팅
VPN_SUBNET="10.0.0.0/8" sudo ./vpn-connect.sh <cookie>
```

`.env` 파일에서도 설정 가능합니다:

```bash
VPN_USERNAME=사용자이름
VPN_PASSWORD=비밀번호
VPN_SERVER=https://vpn.example.com/
VPN_SUBNET=10.0.0.0/8
```

## 파일 구조

```
vpn-bypass/
├── vpn-auto-login.py   # 자동 로그인 스크립트 (Playwright + Gmail API)
├── vpn-connect.sh      # VPN 연결 스크립트 (openconnect + vpn-slice)
├── install.sh          # 설치 스크립트
├── .env                # VPN 자격 증명 (git 추적 제외)
└── README.md
```

## 동작 원리

1. **Playwright** — 헤드리스 Chromium 브라우저로 F5 VPN 포털에 로그인하고 이메일 OTP 인증을 선택
2. **Gmail API** — OAuth 2.0으로 Gmail에 접근하여 `vpn-admin@postech.ac.kr`에서 온 OTP 이메일을 폴링
3. **OTP 자동 입력** — 이메일 제목에서 OTP 코드를 추출하여 자동 입력
4. **MRHSession 쿠키** — 인증 완료 후 브라우저에서 세션 쿠키를 추출
5. **openconnect** — `--protocol=f5` 플래그로 F5 VPN 프로토콜을 사용하고, 쿠키로 인증
6. **vpn-slice** — 기본 VPN 스크립트를 대체하여 지정된 서브넷만 VPN으로 라우팅

## 문제 해결

### 쿠키 만료
`MRHSession` 쿠키는 유효 시간이 제한됩니다. `openconnect` 연결이 실패하면 다시 로그인해야 합니다.

### 다른 VPN 확장 프로그램 간섭
패킷 손실이나 높은 지연이 발생하면 다른 VPN 관련 네트워크 확장을 확인합니다:
```bash
systemextensionsctl list
```
시스템 설정에서 활성 VPN 확장을 비활성화합니다:
> 시스템 설정 → 일반 → 로그인 항목 및 확장 → 네트워크 확장

### Gmail OTP 수신 실패
- `~/.gmail-mcp/credentials.json`이 존재하는지 확인
- OAuth 토큰이 만료된 경우 `npx @gongrzhe/server-gmail-autoauth-mcp auth`로 재인증
- Google Cloud Console에서 본인 이메일이 테스트 사용자에 추가되어 있는지 확인

### Playwright 브라우저 오류
```bash
python3 -m playwright install chromium
```

## 라이선스

MIT
