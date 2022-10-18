#!/bin/bash

# domain.conf
# doamin,acm_region
# xxxx,tokyo
# xxxx,virginia

# slack webhookurl
webHookUrl="xxxx"
_pwd=$(cd $(dirname "$0") && pwd)


_check_current_process() {
  count=$(ps -ef |grep 'autoSsl.sh' |grep -v "grep" |wc -l)
  if [ "$count" -gt "2" ];then
    echo "Already run !"
    exit 1
  fi
}

_send_to_slack() {
  message=$1
  curl -d "{\"text\": \"<!channel> ACME ERROR: $message \"}" -H 'Content-Type: application/text' "$webHookUrl" 1>/dev/null
}

_check_current_process

while read line || [[ -n ${line} ]]; do
  info=(${line//,/ })
  domain=${info[0]}
  region=${info[1]}

  if [ "$region" = "tokyo" ]; then
    _deploy_region="--deploy-hook aws_acm_tokyo"
  elif [ "$region" = "virginia" ]; then
    _deploy_region="--deploy-hook aws_acm_virginia"
  else
    _send_to_slack "*$domain* region error."
    continue
  fi

  # 验证 域名 是否正确解析
  random_file=$(cat /proc/sys/kernel/random/uuid)
  uuid=$(cat /proc/sys/kernel/random/uuid)
  echo "$uuid" >/data/public/.well-known/acme-challenge/"$random_file"
  curl_res=$(curl -sL "$domain"/.well-known/acme-challenge/"$random_file")
  rm -f /data/public/.well-known/acme-challenge/"$random_file"
  if [ "${curl_res:0:36}" != "$uuid" ]; then
    continue
  fi

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

  # 部署 ssl 证书 到 aws ACM
  deploy_out=$(/root/.acme.sh/acme.sh --deploy -d "$domain" "$_deploy_region")
  _ret=$?
  if [ "$_ret" != "0" ]; then
    echo "certificate deploy to acm($region) fail" >>"$_pwd"/logs/"$domain".log
    echo "$deploy_out" >>"$_pwd"/logs/"$domain".log
    _send_to_slack "*$domain* SSL certificate deploy to ACM($region) fail."
    continue
  fi

  # 成功后删除 domain.conf 的 域名
  sed -i "/$domain/d" "$_pwd"/domain.conf

  if [ "$region" = "tokyo" ]; then
    # 更新 nlb 证书
    /bin/bash "$_pwd"/addNlbCert.sh "$domain"
  elif [ "$region" = "virginia" ]; then
    # 更新 CloudFront 证书 
    # 待定
    :
  fi
done <"$_pwd"/domain.conf