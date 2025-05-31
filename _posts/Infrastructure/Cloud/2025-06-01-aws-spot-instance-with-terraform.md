---
title: AWS Teraform, Spot Instance를 이용하여 부하 발생기 구축하기
author: hi0yoo
date: 2025-06-01 01:40:00 +0900
categories:
  - Infrastructure
  - Cloud
tags:
  - infra
  - aws
  - spot
  - terraform
  - artillery
render_with_liquid: false
---
로컬에서 Application + Artillery 구동하니 적절한 테스트가 불가능하여, 부하 발생기를 다른 머신으로 옮기고자 했다.

AWS Spot Instance를 알게되어 사용해보기로 했다.


## Spot Instance ?

[AWS 페이지](https://aws.amazon.com/ko/ec2/spot/)를 링크로 남긴다.

핵심만 보자면, AWS EC2 리소스 중에서 남는 부분을 저렴하게 제공하는 서비스이다.

한국 리전 기준, Spot Instance c6g.large 모델 비용은 **$0.0262/hour**이다.

하루 2시간씩 30일 기준, $0.0302 * 60 = $1.58/month, 한화 약 2200원 내외로 매우 저렴하게 이용할 수 있으니 테스트용으로는 적절하다.


### Spot Instances vs On-Demand Instances

| 비교      | Spot Instances                                                                                                                                                                            | On-Demand Instances                               |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| 시작 시간   | 스팟 인스턴스 요청이 활성 상태이고 용량이 가용 상태인 경우 즉시 시작할 수 있습니다.                                                                                                                                          | 수동 시작을 요청했고 용량이 가용 상태인 경우에만 즉시 시작할 수 있습니다.        |
| 가용 용량   | 용량이 가용 상태가 아닌 경우 용량이 가용 상태가 될 때까지 스팟 인스턴스 요청이 계속해서 자동으로 시작 요청을 합니다.                                                                                                                       | 시작 요청을 할 때 용량이 가용 상태가 아닌 경우 용량 부족 오류(ICE)가 발생합니다. |
| 시간당 가격  | 스팟 인스턴스의 시간당 가격은 장기적인 수요와 공급에 따라 다릅니다.                                                                                                                                                    | 온디맨드 인스턴스의 시간당 가격은 고정된 가격입니다.                     |
| 리밸런싱 권고 | 인스턴스 중단 위험이 높아질 때 실행 중인 스팟 인스턴스에 대해 Amazon EC2가 생성하는 신호입니다.                                                                                                                               | 온디맨드 인스턴스가 중단(중지, 최대 절전 또는 종료)되는 시간을 결정합니다.       |
| 인스턴스 중단 | Amazon EBS 지원 스팟 인스턴스를 중지하고 시작할 수 있습니다. 또한 Amazon EC2에서 용량을 더 이상 사용할 수 없는 경우 개별 스팟 인스턴스를 [중단](https://docs.aws.amazon.com/ko_kr/AWSEC2/latest/UserGuide/spot-interruptions.html)할 수 있습니다. | 온디맨드 인스턴스가 중단(중지, 최대 절전 또는 종료)되는 시간을 결정합니다.       |

> 출처 : https://docs.aws.amazon.com/ko_kr/AWSEC2/latest/UserGuide/using-spot-instances.html



## AWS IAM 사용자 및 인증키 생성

Terraform이 AWS에 접근하려면 인증 정보가 필요하다.

1. 루트 계정으로 접속하여 [IAM](https://us-east-1.console.aws.amazon.com/iam/home?region=ap-southeast-2#/home) 으로 이동
2. 사용자 생성
	1. AWS Management Console에 대한 사용자 액세스 권한 제공 << 프로그래밍 방식으로 엑세스 할 것이기 때문에 해당 권한은 줄 필요 없다.
	2. 권한 부여
3. Access Key 생성
	1. Command Line Interface(CLI) 선택
	2. 생성된 Access Key, Secret Access Key 는 별도로 저장해둔다.

테스트용이기 때문에 편의를 위해 AdministratorAccess(전체 권한)을 부여한 사용자를 만들었다.


## 로컬 환경에 AWS CLI, Terraform 설치 및 인증 설정

### 설치

Mac 환경이라면 아래 명령을 통해 AWS CLI와 Terraform을 설치한다.

```bash
brew install awscli
brew install terraform
```

### 인증 설정

설치가 완료되면 아래 명령을 통해 AWS 인증 설정을 진행한다.

```bash
aws configure
```

프롬프트에 다음 정보를 입력한다.

```
AWS Access Key ID: [발급받은 Access Key]
AWS Secret Access Key: [발급받은 Secret Access Key]
Default region name: ap-northeast-2
Default output format: json
```

리전과 출력 포맷은 원하는 것을 입력하면 된다.

> 일부 리전은 특정 인스턴스 타입의 Spot 인스턴스 재고가 부족할 수 있다.
> 지연시간, 비용 등을 참고해서 적절한 리전을 선택하도록 한다.<br>
> 출력 포맷은 json, table, text, yaml 등 다양한 포맷을 지원한다.

### Key Pair, Subnet, Security Group 생성

AWS 콘솔에서 직접 생성하여 ID만 기록해둬도 상관없다. 편의를 위해 Terraform으로 만들었다.

개인키/공개키는 미리 만들어둔다.

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/spot-artillery-key -N ""
```


## Terraform 설정을 위한 파일 작성

Terraform은 현재 디렉토리 내의 모든 .tf 파일을 자동으로 읽어서 하나로 구성한다.

특정 디렉토리에 Terraform 설정 파일들을 작성해준다.

### variables.tf

외부에서 전달받을 변수들을 정의한 파일이다.
굳이 작성 안하고 하드코딩으로 작성해도 무방하다.

```hcl
variable "region" {
  default = "ap-northeast-2"
}

variable "availability_zones" {
  default = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"]
}

variable "key_name" {
  default = "your_key_name" # 예시
}

variable "public_key_path" {
  default = "~/.ssh/your-public-key.pub" # 예시
}

variable "ami_id" {
  default = "ami-08bfb0e99afebd8a3"  # Ubuntu 22.04 LTS (ARM64, ap-northeast-2)
}

variable "instance_type" {
  default = "c6g.large"
}

variable "spot_max_price" {
  default = "0.04"
}
```

### main.tf

Terraform의 메인 파일로 EC2 Spot 인스턴스를 정의한다.

```hcl
provider "aws" {
  region = var.region
}

# 사용자의 SSH 공개키를 AWS에 등록한다.
resource "aws_key_pair" "default" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# VPC 생성
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "terraform-vpc" }
}

# 퍼블릭 서브넷 생성
resource "random_integer" "az_choice" {
  min = 0
  max = 2
}

locals {
  selected_az = element(var.availability_zones, random_integer.az_choice.result)
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = local.selected_az
  tags = {
    Name = "terraform-public-subnet"
  }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id
  tags = { Name = "terraform-igw" }
}

# 라우팅 테이블
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "terraform-public-rt" }
}

# 라우팅 테이블과 서브넷 연결
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 보안 그룹 (SSH 및 HTTP 허용)
resource "aws_security_group" "default" {
  name        = "terraform-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 실무에서는 본인의 고정 IP로 제한
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-sg" }
}

# Spot 인스턴스 (Artillery 부하 테스트용)
resource "aws_instance" "artillery_spot" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.default.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.default.id]

  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = var.spot_max_price
      spot_instance_type             = "one-time"
      instance_interruption_behavior = "terminate"
    }
  }

  associate_public_ip_address = true
  user_data                   = file("user-data.sh") # 초기 스크립트 실행 (예: Node.js + Artillery 설치)

  tags = {
    Name = "artillery-spot"
  }
}
```


### user-data.sh

user-data.sh 파일은 EC2 인스턴스가 부팅될 때 자동으로 실행되는 초기화 스크립트이다.
처음 서버를 띄울 때 필요한 설정을 자동화할 수 있도록 도와준다.

```bash
#!/bin/bash
set -e

# 패키지 업데이트
apt-get update -y
apt-get upgrade -y

# 유틸리티 도구 설치
apt-get install -y git tmux htop curl unzip

# Node.js 설치 (LTS 버전)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Artillery 1.7.9 버전 설치
npm install -g artillery@1.7.9

# 확인 로그 출력
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"
echo "artillery version: $(artillery -V)"
```


### outputs.tf

output은 Terraform 실행 후 유용한 리소스 정보를 화면에 출력하거나 외부로 전달하기 위해 사용하는 기능이다.
기능을 사용하려면 outputs.tf 를 작성하면 된다.

instance_public_ip는 부하 테스트용 EC2에 직접 접속하거나, 테스트 대상 애플리케이션에서 접속 가능한 주소를 자동으로 확인할 수 있게 해준다.

```hcl
# EC2 퍼블릭 IP 출력
output "instance_public_ip" {
  value = aws_instance.artillery_spot.public_ip
}
```


### 인스턴스 실행시 데이터 파일 포함

인스턴스 실행시에 데이터 파일을 포함시키고 싶다면 user-data.sh에 작성하면 된다.

간단한 파일이라면 -cat << EOF 를 통해, 복잡하거나 바이너리 포함 파일이라면 base64를 활용하여 전달하면 된다.

```bash
#!/bin/bash
set -e

# 패키지 업데이트
apt-get update -y
apt-get upgrade -y

# 유틸리티 도구 설치
apt-get install -y git tmux htop curl unzip

# Node.js 설치 (LTS 버전)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Artillery 1.7.9 버전 설치
npm install -g artillery@1.7.9

# 테스트 파일 디렉토리 생성
mkdir -p /home/ubuntu/loadtest
cd /home/ubuntu/loadtest

# 테스트 스크립트 파일 복원 (base64 디코딩)
# order-test.yml
cat <<EOF | base64 -d > order-test.yml
<BASE64_ENCODED_ORDER_TEST_YML>
EOF

# processor.js
cat <<EOF | base64 -d > processor.js
<BASE64_ENCODED_PROCESSOR_JS>
EOF

# 설치 확인 로그 출력
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"
echo "artillery version: $(artillery -V)"
```

전달할 파일을 아래 명령을 통해 base64로 인코딩한다.

```bash
base64 ./script/order-test.yml > order-test.yml.b64
```

인코딩된 내용을 복사하여 <BASE64_ENCODED_ORDER_TEST_YML> 부분에 끼워넣어서 전달하도록 한다.

이게 싫으면 직접 인스턴스로 전달하면 된다. (파일 용량이 크면 강제로...)

```bash
scp -i ~/.ssh/your_key_name ./loadtest/order-test.yml ubuntu@<EC2 IP>:/home/ubuntu
# or
# scp -i ~/.ssh/your_key_name -r ./loadtest/ ubuntu@<EC2_IP>:/home/ubuntu/
```



## Terraform 실행

### 초기화

실행 전에 Terraform 초기화를 진행해야 한다. 현재 디렉토리에서 .terraform 디렉토리를 설정하는 작업이므로, 디렉토리별 최초 1회 작업이 필요하다.

아래 명령을 수행하면 모듈 및 프로바이더를 초기화한다.

```bash
terraform init
```

### 인스턴스 생성

아래 명령을 수행하면 변경 내용을 검토하는 내용과, 해당 내용을 수행할지 여부를 묻는 내용이 출력된다.

```bash
terraform apply
```

`yes`를 입력해서 수행한다.

### 인스턴스 접속 테스트

인스턴스 public ip 출력 설정을 했다면 해당 IP로 접속하여 인스턴스를 확인해보도록 하자.

```bash
ssh -i ~/.ssh/your_key_name ubuntu@<출력된 퍼블릭 IP>
```

ssh -i ~/.ssh/spot-artillery-key ubuntu@<출력된 퍼블릭 IP>

### 인스턴스 종료

인스턴스 사용이 끝났거나 비용 절감을 위해 종료하려면 아래 명령을 수행한다.

```bash
terraform destroy
```

Spot 인스턴스, VPC, 서브넷, 키페어 등이 모두 제거된다.


