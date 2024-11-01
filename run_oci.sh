#!/bin/bash

# OCI 세션 인증
# 위치를 선택하세요. 예시에서는 ca-toronto-1을 사용했습니다. 사용자에 따라 다를 수 있습니다.
# 프로필 이름을 묻는 경우, "DEFAULT" 혹은 사용자가 설정한 프로필 이름을 입력하세요.

# Oracle Cloud 계정 테넌시 ID
tenancy_id=""
# Ubuntu 22.04 ARM 이미지 ID
image_id=""
# 서브넷 ID
subnet_id=""

# 가용성 도메인
avail_domain=""

# SSH 키 (authorized_keys에 추가할 SSH 키)
sshkey=""
# 변수 설정 모드
setup=1
silent=0

# VM 사이즈 설정
cpus=4       # CPU 코어 수
ram=24       # 메모리 크기 (GB 단위)

# 세션 인증 파라미터
profile="DEFAULT"
config_file="$HOME/.oci/config"

auth_params=" --config-file $config_file --profile $profile  --auth security_token "

request_interval=60  # 요청 간격 (초 단위)
max=$((60 * 60 * 24 / request_interval))

#if [[ $sshkey ]]; then
#    ssh_key="--metadata {'ssh_authorized_keys':'$sshkey'}"
#fi

# SSH 키 값을 JSON 형식으로 정확히 전달하기 위해 jq로 JSON 데이터 생성
metadata_json=$(jq -n --arg ssh_key "$sshKey" '{"ssh_authorized_keys": $ssh_key}')

if [[ $setup -eq 1 ]]; then
    echo "설정 모드 활성화! 필요한 정보를 수집한 후, setup 변수를 0으로 설정하세요."
    echo -e "\n### 이미지 목록: ###"
    oci compute image list --all -c $tenancy_id $auth_params | jq -r '.data[] | select(.["display-name"] | contains("aarch64")) | "\(.["display-name"]): \(.id)"'

    echo -e "\n### 서브넷 목록: ###"
    oci network subnet list -c $tenancy_id $auth_params | jq -r '.data[] | "\(.["display-name"]) : \(.id)"'

    echo -e "\n### 가용성 도메인 목록: ###"
    oci iam availability-domain list -c $tenancy_id $auth_params | jq -r '.data[] | "\(.name)"'

    read -p "계속하려면 아무 키나 누르세요..."
    exit
fi

start_time=$(date +%s)
for ((i = 0; i < max; i++)); do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    
    if [[ $i -gt 1 ]]; then
        sleep_time=$((request_interval - elapsed_time))
        if [[ $sleep_time -gt 0 ]]; then
            sleep $sleep_time
        fi
    fi
    
    start_time=$(date +%s)
    echo "$i of $max - $(date)"
    
    if (( i % 10 == 0 && i > 0 )); then
        echo "토큰 갱신 중..."
        oci session refresh --profile $profile
    fi
    response=$(oci compute instance launch --no-retry --metadata "$metadata_json" --availability-domain "$avail_domain" $auth_params --compartment-id "$tenancy_id" --image-id "$image_id" --shape 'VM.Standard.A1.Flex' --shape-config "{'ocpus':$cpus,'memoryInGBs':$ram}" --subnet-id "$subnet_id" 2>&1)

    if [[ $silent -eq 0 ]]; then
        echo "응답: $response"
    fi

    json=$(echo "$response" | jq '.')

    if [[ $silent -eq 0 ]]; then
        echo "JSON: $json"
    fi

    if [[ $(echo "$json" | jq -r '.data.id') ]]; then
        echo "컨테이너 생성 완료! 인스턴스를 확인하세요."
        echo $(echo "$json" | jq -r '.data.id')
        read -p "계속하려면 아무 키나 누르세요..."
        exit
    fi

    status=$(echo "$json" | jq -r '.status')
    message=$(echo "$json" | jq -r '.message')

    case $status in
        429)
            echo "요청 과다 - 딜레이 증가 ($request_interval)"
            request_interval=$((request_interval + 1))
            ;;
        200)
            echo "상태 200 = 성공?"
            read -p "계속하려면 아무 키나 누르세요..."
            exit
            ;;
        401)
            echo "상태 401 = 인증 실패 또는 만료."
            echo "oci session authenticate 명령을 실행하세요."
            read -p "계속하려면 아무 키나 누르세요..."
            exit
            ;;
        *)
            echo "오류 확인 불가! 성공?"
            read -p "계속하려면 아무 키나 누르세요..."
            exit
            ;;
    esac
done
