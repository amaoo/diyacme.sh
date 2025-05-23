#!/usr/bin/bash
# Written by amao <lzmyrs@gmail.com>

ali_oss_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  
  ALI_CERT_REGION="${ALI_CERT_REGION:-$(_readdomainconf ALI_CERT_REGION)}"
  if [ -z "$ALI_CERT_REGION" ]; then
    _err "not find ALI_CERT_REGION"
    _info "Default deploying to ALI ACM of cn-hangzhou"
    ALI_CERT_REGION="cn-hangzhou"
    _savedomainconf ALI_CERT_REGION "$ALI_CERT_REGION"
  fi
  
  ALI_OSS_REGION="${ALI_OSS_REGION:-$(_readdomainconf ALI_OSS_REGION)}"
  if [ -z "$ALI_OSS_REGION" ]; then
    _err "not find ALI_OSS_REGION"
    _info "Default deploying to ALI OSS of cn-hangzhou"
    ALI_OSS_REGION="cn-hangzhou"
    _savedomainconf ALI_OSS_REGION "$ALI_OSS_REGION"
  fi

  ALI_OSS_DOMAIN="${ALI_OSS_DOMAIN:-$(_readdomainconf ALI_OSS_DOMAIN)}"
  if [ -z "$ALI_OSS_DOMAIN" ]; then
    _err "not find ALI_OSS_DOMAIN"
    return 1
  fi

  ALI_OSS_BUCKET="${ALI_OSS_BUCKET:-$(_readdomainconf ALI_OSS_BUCKET)}"
  if [ -z "$ALI_OSS_BUCKET" ]; then
    _err "not find ALI_OSS_BUCKET"
    return 1
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cert_region "$ALI_CERT_REGION"
  _debug _oss_region "$ALI_OSS_REGION"
  _debug _oss_domain "$ALI_OSS_DOMAIN"
  _debug _oss_bucket "$ALI_OSS_BUCKET"

  _cert_name="${_cdomain}_"$(date "+%y%m%d%H%M")
  # 将证书和私钥内容读入变量，去掉行尾换行（保持 PEM 内容连续）
  _cert_content=$(sed 's/\r$//g' "$_cfullchain" | tr -d '\n')
  _key_content=$(sed 's/\r$//g' "$_ckey" | tr -d '\n')

  # 生成签名
  _generate_signature
  # ---------------------- 发送请求 ----------------------
  _request_url="https://cas.aliyuncs.com/?${_query_string}&Signature=${_signature_encoded}"
  #echo "Sending request to ACM: $request_url" >&2
  # 使用 curl 发送请求，捕获 HTTP 状态码
  _http_response=$(curl -s -w "%{http_code}" "$_request_url")
  _http_code="${_http_response: -3}"
  _body="${_http_response:0:-3}"

  # ---------------------- 结果处理 ----------------------
  if [[ "$_http_code" != "200" ]]; then
    _debug "Error: HTTP $_http_code" >&2
    _debug "Response: $_body" >&2
    _send_notify "ACME Error: deploy to ALI ACM fail"
    return 1
  fi

  _info "Upload successful"

  _cert_id=$(echo "$_body" | grep -o '"CertId":[0-9]*' | sed 's/[^0-9]*//')



  # ---------------------- 更新OSS证书 ----------------------
  # 生成日期和时间
  _oss_date=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S GMT")
  # 构造请求内容
  _oss_request_content="
  <BucketCnameConfiguration>
    <Cname>
      <Domain>${ALI_OSS_DOMAIN}</Domain>
      <CertificateConfiguration>
        <CertId>${_cert_id}-${ALI_CERT_REGION}</CertId>
        <Force>true</Force>
      </CertificateConfiguration>
    </Cname>
  </BucketCnameConfiguration>"
  _oss_content_md5=$(echo -n "${_oss_request_content}" | openssl dgst -md5 -binary | openssl enc -base64)
  _oss_content_type="application/xml"

  # 构造签名字符串
  _oss_canonical_resource="/${ALI_OSS_BUCKET}/?cname&comp=add"
  _oss_string_to_sign="POST\n${_oss_content_md5}\n${_oss_content_type}\n${_oss_date}\n${_oss_canonical_resource}"

  # 计算签名
  _oss_signature=$(echo -en "${_oss_string_to_sign}" | openssl sha1 -hmac "${Ali_Secret}" -binary | openssl enc -base64)

  # 发送请求
  _oss_request_url="https://${ALI_OSS_BUCKET}.oss-${ALI_OSS_REGION}.aliyuncs.com/?cname&comp=add"
  _info $_oss_request_url

  _oss_http_response=$(curl -s -w "%{http_code}" -X POST \
    -H "Authorization: OSS ${Ali_Key}:${_oss_signature}" \
    -H "Date: ${_oss_date}" \
    -H "Content-Type: ${_oss_content_type}" \
    -H "Content-MD5: ${_oss_content_md5}" \
    -d "${_oss_request_content}" \
    "$_oss_request_url")  

  _oss_http_code="${_oss_http_response: -3}"
  _oss_body="${_oss_http_response:0:-3}"
  if [[ "$_oss_http_code" != "200" ]]; then
    _debug "Error: HTTP $_oss_http_code" >&2
    _debug "Response: $_oss_body" >&2
    _send_notify "ACME Error: deploy to OSS fail"
    return 1
  fi

  _info "Deploy successful. Response: $_oss_body"
  _send_notify "ACME Success: deploy $_cdomain to ALI OSS"
  return 0
}


# ---------------------- 生成签名 ----------------------
_generate_signature(){
  # ---------------------- 构造签名所需参数 ----------------------
  # 时间戳（UTC 格式带 Z）
  _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # 唯一随机串
  if command -v uuidgen > /dev/null 2>&1; then
    _signature_nonce=$(uuidgen)
  else
    _signature_nonce="${RANDOM}$(date +%s%N)"
  fi

  # 组织请求参数，并对值进行 URL 编码
  declare -A _params
  _params=(
    ["AccessKeyId"]="${Ali_Key}"
    ["Action"]="UploadUserCertificate"
    ["Format"]="JSON"
    ["Name"]="${_cert_name}"
    ["Cert"]="$_cert_content"
    ["Key"]="$_key_content"
    ["RegionId"]="${ALI_CERT_REGION}"
    ["SignatureMethod"]="HMAC-SHA1"
    ["SignatureNonce"]="${_signature_nonce}"
    ["SignatureVersion"]="1.0"
    ["Timestamp"]="$_ts"
    ["Version"]="2020-04-07"
  )

  # 对每个参数值进行编码，并构造 key=value 形式的字符串列表
  for key in "${!_params[@]}"; do
    # 注意：CERT 和 Key 的内容中包含非 ASCII 字符，需要正确编码
    _params[$key]="$(_url_encode "${_params[$key]}")"
  done

  # ---------------------- 生成待签名字符串 ----------------------
  # 将参数按键名排序并用 & 拼接
  _query_string=$(for key in "${!_params[@]}"; do echo "$key=${_params[$key]}"; done | sort | tr '\n' '&' | sed 's/&$//')
  # 签名字符串格式：GET&%2F&{URL_Encode(_query_string)}
  _string_to_sign="GET&%2F&$(_url_encode "$_query_string")"

  # ---------------------- 计算签名 ----------------------
  # 使用 HMAC-SHA1 算法，密钥为 AccessKeySecret 后面加 '&'
  _signature=$(printf "%s" "$_string_to_sign" | openssl dgst -sha1 -hmac "${Ali_Secret}&" -binary | openssl base64)
  # URL 编码签名值
  _signature_encoded=$(_url_encode "$_signature")
}


# ---------------------- URL 编码函数（遵循 RFC3986） ----------------------
_url_encode() {
  local raw="$1"
  local length=${#raw}
  local i ch hex
  for (( i = 0; i < length; i++ )); do
    ch="${raw:i:1}"
    case "$ch" in
      [a-zA-Z0-9.~_-]) printf '%s' "$ch" ;;
      *)
        printf '%%%02X' "'$ch"
        ;;
    esac
  done
}
