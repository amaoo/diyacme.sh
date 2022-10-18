#!/bin/bash

# slack webhookurl
webHookUrl="xxxx"
_pwd=$(cd $(dirname "$0") && pwd)
_listener_arn='xxxx' #nlb 监听器 arn

_send_to_slack() {
  message=$1
  curl -d "{\"text\": \"<!channel> ACME ERROR: $message \"}" -H 'Content-Type: application/text' "$webHookUrl" 1>/dev/null
}

_read_acme_doamin_conf() {
  _config_path="/root/.acme.sh/$1/$1.conf"
  _key="$2"
  if [ -f "$_config_path" ]; then
    _sdv="$(
      eval "$(grep "^$_key *=" "$_config_path")"
      eval "printf \"%s\" \"\$$_key\""
    )"
    printf "%s" "$_sdv"
  fi
  return 1
}

domain=$1
confKey="Acm_Arn_tokyo"

_cert_arn=$(_read_acme_doamin_conf "$domain" "$confKey")

# 在 nlb 中添加证书
_elb_res=$(aws elbv2 add-listener-certificates --listener-arn $_listener_arn --certificates CertificateArn="$_cert_arn" --region ap-northeast-1)
_ret=$?
if [ "$_ret" != "0" ]; then
  echo 'nlb certificate add fail' >>"$_pwd"/logs/"$domain".log
  echo "$_elb_res" >>"$_pwd"/logs/"$domain".log
  _send_to_slack "*$domain* nlb certificate add fail."
  return 1
fi