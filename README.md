# PB팀메이커 (PowerScore Balanced Team Maker) - 다중 디스코드 서버 버전

PB팀메이커(PowerScore Balanced Team Maker)는 여러 디스코드 서버가 각자 독립된 선수 명단, 통계, 팀 이름, 랭킹을 운영하는 Vercel + Supabase 웹앱입니다.

## v9 업데이트 적용 순서 (Discord 로그인 전환)
1. 프로젝트 전체 파일을 기존 GitHub 저장소 루트에 업로드해 덮어씁니다.
2. v8에서 이미 `server-multi-tenant.sql`을 실행했다면 다시 실행할 필요가 없습니다. 아직 실행하지 않았다면 SQL Editor에서 실행하세요.
3. Supabase Authentication > Providers > Discord에서 Discord 로그인을 활성화합니다.
4. Discord Developer Portal에서 애플리케이션을 만들고 OAuth2 설정의 Client ID와 Client Secret을 확인합니다. Supabase가 안내하는 Callback URL을 Discord OAuth2 Redirects에 등록하고, Client ID/Secret을 Supabase Discord Provider에 입력합니다.
5. Supabase Authentication > URL Configuration에서 Site URL과 Redirect URLs에 실제 배포 주소를 등록합니다.
6. GitHub에 Commit하면 Vercel이 자동 재배포됩니다. 기존 Supabase URL/anon key 환경변수는 그대로 사용합니다.

## v9 사용법
- Discord 로그인 후 첫 접속에서 사이트 닉네임(2~20자)을 설정합니다. Supabase Auth 세션은 브라우저에 유지되며, 상단 Discord 로그아웃 버튼으로 로그아웃할 수 있습니다.
- 로그인한 Discord 계정은 서버를 평생 1개만 생성할 수 있습니다. 이 제한은 DB의 `server_creation_claims`에서 확인하므로 서버가 나중에 삭제되어도 다시 만들 수 없습니다.
- 서버 생성 시 서버 이름, 서버 관리자 비밀번호(8자 이상), 공개/비공개 여부를 설정합니다. 비공개 서버는 별도의 열람 비밀번호(8자 이상)를 설정합니다.
- 서버 관리 메뉴의 검색창에서 서버 이름을 검색할 수 있습니다. 공개/비공개 여부와 참여자 수가 표시됩니다. 비공개 서버의 프로필/선수 데이터는 올바른 열람 비밀번호를 입력해야 열립니다.
- 서버 카드의 `프로필/보안 설정`에서 서버 이름, 프로필 이미지 URL, 공개/비공개 여부, 열람 비밀번호를 변경할 수 있습니다. 프로필 이미지는 웹에서 접근 가능한 이미지 URL을 입력합니다.
- 서버 소유자는 자동으로 서버 관리자입니다. 서버 관리자 비밀번호로 로그인한 사용자도 해당 서버의 관리자로 등록됩니다. 서버 관리자 및 부관리자는 해당 서버의 선수/전적/팀 데이터와 서버 프로필 설정을 관리할 수 있습니다.
- 서버 가입 버튼으로 참여할 수 있습니다. 비공개 서버는 열람 비밀번호를 입력해야 가입됩니다. 참여자는 서버 데이터 열람 및 가입 상태를 유지합니다.
- 참여자 관리에서 서버 관리자는 참여자 목록을 확인할 수 있습니다. 명령에 `kick`을 입력하면 강퇴, `promote`를 입력하면 부관리자로 지정할 수 있습니다. 부관리자 지정/강퇴는 서버 관리자만 가능하며 서버 소유자 계정은 강퇴되지 않습니다.
- 서버 관리자 비밀번호는 상단 `서버 비밀번호 변경`에서 변경할 수 있습니다. 열람 비밀번호는 `프로필/보안 설정`에서 변경합니다. 두 비밀번호는 별도로 관리됩니다.

## 보안 모델 및 주의사항
- 서버 생성 1회 제한, 서버 소유자/부관리자 권한, 비공개 서버 열람 검증, 강퇴/부관리자 지정은 프론트엔드 표시만으로 제한하지 않고 Supabase DB 함수에서 검증합니다.
- 서버 목록은 검색을 위해 서버 이름, 프로필 이미지 URL, 공개 여부, 소유자 ID, 참여자 수만 노출합니다. 서버 비밀번호 해시와 선수 데이터는 목록에서 노출하지 않습니다.
- 공개 서버 데이터는 누구나 열람할 수 있습니다. 비공개 서버 데이터는 열람 비밀번호 또는 해당 서버의 가입 권한이 필요합니다.
- 이미지 업로드 기능이 아니라 이미지 URL 지정 방식입니다. 별도 Supabase Storage 버킷은 필요하지 않습니다.
- 브라우저에는 Supabase anon/publishable 키만 사용합니다. `service_role` 또는 Secret key를 프론트엔드에 넣지 마세요.
- 기존에 만들어진 v7 이전 서버는 소유자 정보가 없으므로 기존 서버 관리자 비밀번호로 로그인해 관리 권한을 등록한 뒤 사용하세요. 새로 생성한 서버부터 Discord 계정 소유권 및 1회 제한이 적용됩니다.

## 기존 프로젝트 참고
`supabase-schema.sql`은 기존 단일 서버 버전의 초기 스키마입니다. 이미 기존 사이트에서 실행했다면 다시 실행할 필요는 없습니다. 다중 서버 기능을 위해 반드시 `server-multi-tenant.sql`을 추가 실행하세요.


## 이전 버전 참고
`supabase-schema.sql`은 단일 서버 초기 스키마입니다. 이미 Supabase에 기존 데이터를 운영 중이라면 초기화하지 말고 v8의 `server-multi-tenant.sql` 마이그레이션만 실행하세요.


### Discord OAuth 설정
1. https://discord.com/developers/applications 에서 New Application을 누릅니다.
2. 애플리케이션의 OAuth2 설정에서 Client ID와 Client Secret을 확인합니다.
3. OAuth2 Redirects에 Supabase Authentication > Providers > Discord에 표시되는 Callback URL을 그대로 추가합니다. 일반적으로 `https://<프로젝트-ref>.supabase.co/auth/v1/callback` 형태입니다.
4. Supabase Dashboard > Authentication > Providers > Discord를 켜고 Discord Client ID와 Client Secret을 입력한 뒤 저장합니다.
5. Supabase Authentication > URL Configuration의 Site URL 및 Redirect URLs에 실제 배포 사이트 주소를 등록합니다.
6. Discord Provider의 로그인 동의 화면에서 앱 이름 등이 표시될 수 있습니다. 앱의 공개/검증 절차는 실제 배포 범위에 따라 Discord 정책을 확인하세요.
