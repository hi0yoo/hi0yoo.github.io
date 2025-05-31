---
title: 애플리케이션 모니터링과 Prometheus, Grafana
author: hi0yoo
date: 2025-05-31 18:00:00 +0900
categories:
  - Backend
  - Monitoring
tags:
  - monitoring
  - prometheus
  - grafana
render_with_liquid: false
---

애플리케이션 성능 테스트를 진행해보면서, 단순히 응답 시간이나 성공률만 측정하는 것만으로는 부족하다는 걸 느꼈다.

시스템이 실제로 어떤 자원을 어떻게 쓰고 있는지, 특정 구간에서 병목이 왜 발생하는지를 지표로 확인하는 체계가 필요했고, 이 과정에서 **모니터링 도구의 필요성**을 체감했다.


## 모니터링 도구 예시

다양한 상황에 맞춰 사용할 수 있는 대표적인 모니터링 도구들은 다음과 같다:

| 도구                      | 설명                                           |
| ----------------------- | -------------------------------------------- |
| **Prometheus**          | 시계열 기반 메트릭 수집 및 저장                           |
| **Grafana**             | 메트릭 시각화 대시보드 도구                              |
| **Elastic Stack (ELK)** | 로그 수집 및 분석 (Elasticsearch, Logstash, Kibana) |
| **Datadog**             | 클라우드 기반 통합 모니터링 서비스                          |
| **New Relic**           | APM, 인프라, 로그 통합 모니터링                         |

---

## Prometheus와 Grafana

### Prometheus

Prometheus는 **오픈소스 시계열 모니터링 시스템**이다.

- **Pull 방식 메트릭 수집**: 타겟의 `/metrics` 엔드포인트로부터 주기적으로 수집
- **시계열 데이터 저장**: `{metric name, labels}` 기반으로 데이터를 저장
- **PromQL** 쿼리 언어 지원으로 다양한 방식으로 데이터 분석이 가능
- 다양한 **Exporter**를 통해 시스템, DB, 애플리케이션 등 확장 가능

### Grafana

Grafana는 **Prometheus 등에서 수집된 메트릭을 시각화**해주는 도구이다.

- **다양한 시각화 지원**: 그래프, 테이블, 게이지 등
- **데이터 소스 연동**: Prometheus 외에도 InfluxDB, MySQL, PostgreSQL 등 지원
- **대시보드 구성**: 사용자 정의 대시보드를 쉽게 구성 가능
- **알림 기능**: 조건 기반으로 Slack, 이메일 등으로 알림 전송 가능

---

## Spring Boot Application 메트릭 수집 및 모니터링 연동

애플리케이션의 메트릭을 수집하고 Prometheus, Grafana와 연동하여 메트릭을 시각화하는 방법이다.

### 애플리케이션 의존성 추가

애플리케이션에 다음 의존성을 추가한다.
```kotlin
dependencies {  
    implementation("org.springframework.boot:spring-boot-starter-actuator")  
    implementation("io.micrometer:micrometer-registry-prometheus")
}
```

micrometer-registry-prometheus 의존성은 Micrometer로 수집한 메트릭을 Prometheus가 이해할 수 있는 형식으로 데이터를 변환하여 제공하는 역할을 한다.

> **Micrometer란?**
> <br>
> **Micrometer**는 Spring Boot의 기본 메트릭 수집 도구로, 다양한 외부 모니터링 시스템(Prometheus, Datadog, New Relic 등)에 연동 가능한 **공통 추상화 계층**을 제공한다.
> HTTP 요청 수, 응답 시간, JVM 메모리, GC 시간 등 다양한 지표를 수집하며, 커스텀 메트릭도 코드 상에서 직접 등록이 가능하다.


spring-boot-starter-actuator 의존성은 애플리케이션의 상태와 각종 정보를 HTTP 엔드포인트로 제공하는 역할을 한다.

> **Actuator란?**
> <br>Spring Boot Actuator는 애플리케이션의 상태와 내부 정보를 HTTP, JMX 등의 방식으로 외부에 노출해주는 기능을 제공한다.
> <br>애플리케이션 헬스 체크, 메트릭 노출, ENV 정보, Bean 목록 등 다양한 정보를 제공할 수 있다.
> <br>Prometheus와 연동시, /actuator/prometheus 엔드포인트가 메트릭 수집 대상이 된다.


### Prometheus, Grafana 설정

설치를 통해 구성하는 방법도 있지만, Docker를 이용해서 모니터링 애플리케이션을 띄웠다.

```yaml
services:  
  prometheus:  
    image: prom/prometheus:latest  
    container_name: prometheus  
    volumes:  
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:  
      - "9090:9090"  
    command:  
      - '--config.file=/etc/prometheus/prometheus.yml'  
      - '--web.enable-lifecycle'
  
  grafana:  
    image: grafana/grafana:latest  
    container_name: grafana  
    ports:  
      - "3030:3000"  
    volumes:  
      - ./grafana:/var/lib/grafana  
    environment:  
      - GF_SECURITY_ADMIN_USER=admin  
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

아래는 프로메테우스 설정 파일 `prometheus.yml` 파일 내용이다.

```yaml
global:  
  scrape_interval: 15s  
  
scrape_configs:  
  - job_name: 'spring-actuator-apps'  
    metrics_path: '/actuator/prometheus'  
    static_configs:  
      - targets: ['host.docker.internal:8080']
```


### Grafana 대시보드 설정

Grafana는 커뮤니티에서 공유한 다양한 대시보드를 ID로 간편하게 가져올 수 있다.  ([대시보드 검색 바로가기↗](https://grafana.com/grafana/dashboards))

아래 대시보드를 Import 하여 사용했다.

- ID 4701 : JVM
- ID 6083 : Spring Boot HikariCP / JDBC
- ID 17175 : Spring Boot Observability (P95, P99 등)




