#!/bin/bash

webHookUrl="xxxx"
_pwd=$(cd $(dirname "$0") && pwd)

_send_to_slack() {
  message=$1
  curl -d "{\"text\": \"<!channel> ACME ERROR: $message \"}" -H 'Content-Type: application/text' "$webHookUrl" 1>/dev/null
}

while read line || [[ -n ${line} ]]; do
  domain=$line

  # 申请 ssl 证书, 默认使用 zerossl
  issus_out_zero=$(/root/.acme.sh/acme.sh --issue -d "$domain" --webroot /data/public/)
  _ret=$?
  if [ "$_ret" != "0" ]; then
    echo "certificate use zerossl apply fail" >>"$_pwd"/logs/"$domain".log
    echo "$issus_out_zero" >>"$_pwd"/logs/"$domain".log
    issus_out_lets=$(/root/.acme.sh/acme.sh --issue -d "$domain" --webroot /data/public/ --server letsencrypt)
    _ret=$?
    if [ "$_ret" != "0" ]; then
      echo "certificate use letsencrypt apply fail" >>"$_pwd"/logs/"$domain".log
      echo "$issus_out_lets" >>"$_pwd"/logs/"$domain".log
      _send_to_slack "*$domain* SSL certificate apply fail."
      continue
    fi
  fi
  export DEPLOY_SSH_USER="root"
  # export DEPLOY_SSH_SERVER="xxxx"
  export DEPLOY_SSH_KEYFILE="filename for private key"
  export DEPLOY_SSH_CERTFILE="filename for certificate file"
  export DEPLOY_SSH_CAFILE="filename for intermediate CA file"
  export DEPLOY_SSH_FULLCHAIN="filename for fullchain file"
  export DEPLOY_SSH_REMOTE_CMD="apachectl graceful"
  
  # 部署 ssl 证书
  deploy_out=$(/root/.acme.sh/acme.sh --deploy -d "$domain" ssh)
  _ret=$?
  if [ "$_ret" != "0" ]; then
    echo "certificate deploy fail" >>"$_pwd"/logs/"$domain".log
    echo "$deploy_out" >>"$_pwd"/logs/"$domain".log
    _send_to_slack "*$domain* SSL certificate deploy fail."
    continue
  fi

  # 成功后删除 domain.conf 的 域名
  sed -i "/$domain/d" "$_pwd"/domain.conf

done <"$_pwd"/domain.conf