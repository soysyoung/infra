# 0017. OpenSearch Dashboards (Helm 공식 차트, 같은 네임스페이스)

- 상태: 적용 (2026-10-30). 사용자가 `09-2` 를 실행하고 브라우저로 로그인했다고 보고했다. `verify/09-2` 도 통과했다(저장 객체 조회 200, 127.0.0.1:5601 302, [verify/README.md](../../scripts/verify/README.md)). 아래 '미검증' 중 해소된 것은 '적용 결과' 에 적었다

## 상황
OpenSearch([ADR 0014](0014-opensearch-single-node.md))는 `kubectl port-forward` 후 `https://localhost:9200` 으로 접속되고, 브라우저에서는 JSON 만 보인다 (2026-10-28 사용자가 확인: 3.8.0 응답). 인덱스와 k-NN 쿼리를 살펴볼 웹 UI 가 없다.

## 확인한 것 (2026-10-28)
출처: [Installing OpenSearch Dashboards using Helm](https://docs.opensearch.org/latest/install-and-configure/install-dashboards/helm/), 차트 저장소 태그 `opensearch-dashboards-3.8.0` 의 `Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/_helpers.tpl`.
- 차트 `opensearch/opensearch-dashboards`, 태그 3.8.0 은 version 과 appVersion 이 모두 3.8.0 이다. OpenSearch 와 같다.
- 기본 `opensearchHosts` 가 `https://opensearch-cluster-master:9200` 이다. 같은 네임스페이스에 설치하면 그대로 맞는다. 공식 문서도 이 서비스에 연결한다고 적는다.
- Service 는 기본 ClusterIP 5601 이다. 접속은 `kubectl port-forward svc/<이름> 5601` 후 `http://localhost:5601`, `admin` 과 OpenSearch 설치 때 정한 관리자 비밀번호로 로그인한다 (공식 문서). 파드가 Ready 여도 약 1분은 503 이 나올 수 있다.
- `opensearchAccount.secret` 을 주면 템플릿이 그 Secret 의 **`username`, `password`, `cookie` 세 키**를 `OPENSEARCH_USERNAME`, `OPENSEARCH_PASSWORD`, `COOKIE_PASS` 환경변수로 읽는다. 키가 하나라도 없으면 파드가 시작하지 못할 것이다 (템플릿 읽기로 안 사실이고 시험은 아직). 그래서 ADR 0014 의 `opensearch-admin` Secret(키 `password` 하나)을 재사용하지 않고 새 Secret 을 만든다.
- `fullnameOverride` 가 Deployment 와 Service 이름이 된다 (`_helpers.tpl`).
- 차트 기본 리소스는 100m, 512M 이다.

## 결정
- **차트 3.8.0**, OpenSearch 와 같은 버전 (`OPENSEARCH_DASHBOARDS_CHART_VERSION`, [versions.md](../versions.md)). 네임스페이스 `opensearch`, 릴리스와 Service 이름 `opensearch-dashboards`.
- 접속은 [ADR 0011](0011-no-nodeport-https-via-tailscale-serve.md) 의 원칙을 따른다: NodePort 와 Ingress 를 쓰지 않고 ClusterIP 에 port-forward 한다. 터미널을 닫으면 끊기는 것을 막으려고 `09-2` 가 systemd 서비스 `opensearch-dashboards-port-forward`(`127.0.0.1:5601`, `Restart=always`)를 만든다. `07-1` 과 같은 방식이고 2026-10-30 에 추가했다 (아직 실행 전이라 미시험). 이 PC 의 Windows 브라우저는 `http://localhost:5601`. 다른 tailnet 기기용 `tailscale serve` 는 만들지 않았다.
- Dashboards 가 OpenSearch 에 로그인하는 계정은 **`admin`** (`.env` 의 `OPENSEARCH_ADMIN_PASSWORD`) 이다. 새 Secret `opensearch-dashboards-account` 에 `09-2` 가 만든다. `cookie` 는 32자 무작위로 만들고 다시 실행해도 유지한다.
  - 왜 admin 인가: 이미지 기본값은 데모 내부 사용자(`kibanaserver`)를 쓰는 것으로 알려져 있지만, 그 비밀번호가 이 설치에서 무엇인지 확인하지 못했다. 알려진 기본 비밀번호에 기대지 않으려고 이미 정한 관리자 비밀번호를 쓴다. 대가는 Dashboards 가 최고 권한으로 접속한다는 것이고, 전용 최소 권한 계정은 다음 과제다.
- 리소스는 requests = limits 로 메모리 1Gi, CPU 250m~1 로 올린다 (기본 512M 이 부족할 것이라는 **추정**이다. 실측하지 않았다).
- 설정 파일(`config`)은 주지 않는다. 이미지 기본 설정을 쓴다. 자체 서명 인증서를 받아들이는지는 아래 미검증.

## 미검증 (적용 전)
- `09-2` 와 `verify/09-2` 가 실제로 통과하는지. `verify` 는 Dashboards 가 OpenSearch 의 `.kibana` 인덱스를 읽는 요청(`/api/saved_objects/_find`)이 200 을 주는지로 연결, 인증, 인증서 수락을 함께 본다.
- 이미지 기본 설정이 OpenSearch 의 자체 서명 인증서를 받아들이는지 (확인하지 못했다. 거부되면 로그에 인증서 오류가 나고, 그때 `config` 로 `opensearch.ssl.verificationMode` 를 고친다).
- 메모리 1Gi 가 충분한지, 설치 뒤 WSL 메모리 변화 (`free -m`).
- `values.yaml` 은 태그 3.8.0 에서 쓴 키(`opensearchHosts`, `fullnameOverride`, `opensearchAccount`, `resources`)만 확인했고 다른 값은 읽지 않았다.
- 파드가 GPU 노드 taint 를 피해 CPU 워커에 뜨는지 (ADR 0014 의 OpenSearch 는 그랬다).
- Windows 브라우저에서 `localhost:5601` 접속 (WSL2 의 localhost 전달에 기댄다. 8080 은 이 방식으로 접속된다고 확인했다).

## 적용 결과 (2026-10-30)
- 사용자 보고: `09-2` 실행 후 `http://localhost:5601` 에 `admin` 으로 로그인해 Dashboards 화면에 들어갔다 (Windows 브라우저, port-forward). 이로써 Secret 의 세 키로 파드가 시작했고, Dashboards 가 OpenSearch 의 자체 서명 인증서를 받아들여 연결하며, `localhost:5601` 이 Windows 에서 열린다는 점은 **보고로 확인**됐다 (파드 로그나 `verify/09-2` 출력은 보지 못했다).
- 미해소: 메모리 1Gi 가 충분한지(실측 없음), 설치 뒤 WSL 메모리 변화, 파드 배치 노드, 읽기 전용 계정은 [ADR 0018](0018-opensearch-guest-accounts.md), tailnet 접속(`tailscale serve`)은 [ADR 0019](0019-dashboards-tailscale-serve-funnel.md) 에서 만들었다.

## 같은 날의 사고: 비밀번호를 바꾸려고 `.env` 만 고치고 재설치 (2026-10-28 ~ 10-30)
- 비밀번호를 바꾸려고 `teardown/09-1` 후 `.env` 를 고쳐 `09-1` 을 다시 실행했다. 처음 값은 대문자가 없어서 OpenSearch 설치기가 `Password does not match validation regex` 로 거부했고, 파드가 `CrashLoopBackOff` 로 약 41시간 487회 재시작했다. 두 번째 값(특수문자 추가)도 대문자가 없어 같은 이유로 거부됐다. 원인은 로그의 거부 메시지와, Secret 과 `.env` 값의 문자 종류(값은 출력하지 않고 확인)로 찾았다.
- 대문자를 포함한 값으로 `.env` 를 고치고 `09-1` 을 다시 실행한 뒤 파드를 지워 다시 띄우자 `1/1 Running`, 재시작 0, 새 비밀번호 인증 200, 틀린 비밀번호 401, 클러스터 green, `opensearch-knn` 있음 (읽기 전용으로 확인).
- 교훈: `.env` 만 고쳐서는 이미 초기화된 클러스터의 비밀번호가 바뀌지 않는다 (공식 문서: 초기 비밀번호 변수는 처음 한 번만 읽는다). 바꾸려면 삭제 후 재설치한다. 값이 조건(대문자, 소문자, 숫자, 특수문자 각 1개 이상, 8~100자, zxcvbn strong)을 못 맞추면 파드가 끝없이 재시작하므로, 직접 정하지 않고 줄을 지워 `09-1` 이 만들게 하는 편이 안전하다.
