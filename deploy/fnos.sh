#!/bin/bash
# This deployment required fnos and root

fnos_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _fnos_cert_path="${FNOS_CERT_PATH:-$(_readdomainconf FNOS_CERT_PATH)}"
  if [ -z "$_fnos_cert_path" ]; then
    _err "没找到 Fnos 证书路径"
    return 1
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _fnos_cert_path "$_fnos_cert_path"

  # 放置证书文件
  /bin/cp -f "$_fnos_cert_path"/"$_cdomain".crt "$_fnos_cert_path"/"$_cdomain".crt.bak
  /bin/cp -f "$_fnos_cert_path"/"$_cdomain".key "$_fnos_cert_path"/"$_cdomain".key.bak
  cp -a "$_cfullchain" "$_fnos_cert_path"/"$_cdomain".crt
  cp -a "$_ckey" "$_fnos_cert_path"/"$_cdomain".key
  chmod -R 755 "$_fnos_cert_path/"

  # 更新数据库的证书到期日期
  _expiry_date=$(openssl x509 -enddate -noout -in "$_fnos_cert_path/$_cdomain.crt" | sed "s/^.*=\(.*\)$/\1/")
  _expiry_timestamp=$(date -d "$_expiry_date" +%s%3N)  # 获取毫秒级时间戳

  _info "更新数据库证书的有效期到: $_expiry_date"
  psql -U postgres -d trim_connect -c "UPDATE cert SET valid_to=$_expiry_timestamp WHERE domain='$_cdomain'"
  _info "数据库证书有效期更新完成"

  # 重启服务
  _info "重启服务..."
  systemctl restart webdav.service
  systemctl restart smbftpd.service
  systemctl restart trim_nginx.service

  _info "成功将 $_cdomain 部署到 Fnos"
  _send_notify "成功将 $_cdomain 部署到 Fnos"
  return 0
}
