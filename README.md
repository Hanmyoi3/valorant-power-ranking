# VALORANT 내전 파워랭킹 사이트

기존 파워랭킹 화면을 기반으로 한 Vercel 정적 웹앱 + Supabase 온라인 저장 버전입니다. 새 사이트는 선수 명단이 비어 있는 상태로 시작합니다.

## 포함 기능
- 누구나 랭킹/선수 명단/팀 배정 현황 열람
- Supabase DB에 선수, 통계, 티어, 주챔, 카테고리, 팀 이름 저장
- Supabase Auth 로그인 + `admin_users` 테이블로 관리자 권한 확인
- 관리자만 선수 추가/수정/삭제, 엑셀 업로드, 팀 이름 변경 가능
- 카테고리 기본값: IGL, FLEX, 타격대, 척후대, 감시자, 전략가, 오퍼레이터 + 사용자 정의 카테고리
- 파워점수: 승률 / 2 + 평균 ACS / 10 + 티어 점수 (아이언 1 = 0, 단계별 +2)

## 1. Supabase 설정
1. https://supabase.com 에서 새 프로젝트를 만듭니다.
2. SQL Editor에서 `supabase-schema.sql` 전체를 실행합니다.
3. Authentication > Users에서 관리자 계정을 생성합니다. 이메일은 관리자 이메일로, 비밀번호는 기존에 원했던 `nangyee1`로 설정할 수 있습니다. 다만 공개 사이트이므로 실제 운영에서는 추측하기 어려운 긴 비밀번호를 권장합니다.
4. SQL Editor에서 아래 쿼리의 이메일을 실제 관리자 이메일로 바꿔 실행합니다.

```sql
insert into public.admin_users (user_id)
select id from auth.users where email = 'YOUR_ADMIN_EMAIL'
on conflict do nothing;
```

5. Project Settings > API에서 Project URL과 anon/public key를 복사합니다.
6. `supabase-config.js`의 `YOUR_SUPABASE_PROJECT_URL`, `YOUR_SUPABASE_ANON_KEY`를 실제 값으로 바꿉니다. **service_role 키는 절대 브라우저 파일에 넣지 마세요.**

## 2. Vercel 배포
### 가장 간단한 방법: Vercel Drop
1. `supabase-config.js`에 Supabase Project URL과 anon key를 먼저 입력합니다.
2. Vercel 프로젝트의 Settings > Environment Variables에 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ADMIN_EMAIL`을 등록합니다. `SUPABASE_URL`과 `SUPABASE_ANON_KEY`는 위 Supabase 프로젝트 값, `ADMIN_EMAIL`은 관리자 Auth 이메일입니다.
3. 이 폴더를 압축 해제한 뒤 https://vercel.com/drop 에서 폴더를 업로드합니다.
4. Deploy를 누르면 공개 URL이 생성됩니다.

### GitHub로 지속 배포
1. 이 폴더 안의 파일을 GitHub 저장소 루트에 업로드합니다.
2. https://vercel.com 에서 Add New > Project를 선택하고 해당 저장소를 Import합니다.
3. Framework Preset은 Other, Build Command는 비우고 Output Directory는 `.` 또는 기본값으로 둡니다.
4. Deploy를 누르면 공개 URL이 생성됩니다. 이후 저장소에 push할 때마다 자동 배포됩니다.

## 3. 관리자 사용
사이트 상단 `관리자 모드` 버튼을 누르고 관리자 비밀번호를 입력합니다. 비밀번호는 Vercel API 함수가 서버에서 Supabase Auth에 전달하며, 관리자 이메일은 `ADMIN_EMAIL` 환경변수에만 저장됩니다. 관리자 계정이 `admin_users`에 등록되어 있어야 편집이 가능합니다. 일반 방문자는 공개 열람만 가능합니다.

## 참고
- 사이트는 Supabase 프로젝트 설정 전에는 온라인 데이터를 읽거나 저장하지 않습니다. 먼저 `supabase-config.js`를 설정해야 합니다.
- 랭크/요원 이미지는 외부 Riot 게임 에셋 API/CDN을 사용하므로 외부 네트워크가 필요합니다.
- `app_state`는 현재 전체 사이트 데이터를 JSON 한 행에 저장합니다. 소규모 개인 내전 사이트에 적합합니다. 동시 편집자가 많아지면 선수별 테이블 구조로 확장하는 것이 좋습니다.
- 관리자 로그인은 Vercel `/api/admin-login` 서버리스 함수와 Supabase Auth를 사용합니다. 비밀번호를 프론트엔드 HTML/JS에 하드코딩하지 않습니다.
