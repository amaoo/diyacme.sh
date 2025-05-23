#!/usr/bin/bash
# If certificate already exists in acm it will reimport
# If certificate doesn't exist in acm it will create new import
# Written by amao <lzmyrs@gmail.com>

# This deployment required AWS CLI and iam role

aws_acm_virginia_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _region="us-east-1"
  _info "Deploy certificates to the US East (N. Virginia) of aws acm"

#  _region="${AWS_ACM_REGION:-$(_readdomainconf Aws_Acm_Region)}"
#
#  if [ -z "$_region" ]; then
#    _err "no ACM region to use when deploying $_cdomain"
#    _info "Default deploying to ap-northeast-1"
#    _region="ap-northeast-1"
#  fi
#  _savedomainconf Aws_Acm_Region "$_region"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _region "$_region"

  Acm_Arn_virginia=''
  _arn="${Acm_Arn_virginia:-$(_readdomainconf Acm_Arn_virginia)}"

  if [ -z "$_arn" ]; then
    Le_Keylength="$(_readdomainconf Le_Keylength)"
    _debug Le_Keylength "$Le_Keylength"
    _info "Le_Keylength:$Le_Keylength"
    _arn="$(_get_arn "$_cdomain" "$_region" "$Le_Keylength")"
  fi
  _debug _arn "$_arn"

  _ssl_path="--private-key fileb://$_ckey --certificate fileb://$_ccert --certificate-chain fileb://$_cca"

  _import_type=''
  _import_arn=''
  _ret=''
  
  if [ -z "$_arn" ]; then
    _import_type='Newimport'
    _import_arn=$(aws acm import-certificate --region $_region $_ssl_path)
    _ret="$?"
  else
    _import_type='Reimport'
    _import_arn=$(aws acm import-certificate --region $_region --certificate-arn $_arn $_ssl_path)
    _ret="$?"
  fi

  if [ "$_ret" != "0" ]; then
    _debug _import_type "$_import_type"
    _debug _import_arn "$_import_arn"
    _err "Unable to deploy $_cdomain to ACM in $_region"
    _send_notify "Unable to deploy $_cdomain to ACM in $_region" "ImportType: $_import_type \n acm_arn: ${_import_arn:25:-3}" "slack" 1
    return 1
  else
    _debug _import_type "$_import_type"
    _debug _import_arn "$_import_arn"
    _savedomainconf Acm_Arn_virginia "${_import_arn:25:-3}"
    _info "Success to deploy $_cdomain to ACM in $_region"
    _send_notify "Success to deploy $_cdomain to ACM in $_region" "ImportType: $_import_type \n acm_arn: ${_import_arn:25:-3}" "slack" 0
  fi

  return 0
}

_get_arn() {
  _page='50'
  _next=null
  _keylength="$3"
  _includes_option='--includes keyTypes=RSA_2048'

  if _isEccKey "${_keylength}"; then
    _includes_option='--includes keyTypes=EC_prime256v1'
  fi
  _debug _includes_option "$_includes_option"
  
  while [ "$_next" ]; do
    _debug _next "$_next"
    _listComm="aws acm list-certificates $_includes_option --region $2 --max-items $_page"
    if [ "$_next" == "null" ] || [ -z "$_next" ]; then
      resp=$($_listComm)
    else
      resp=$($_listComm --starting-token $_next)
    fi
    [ "$?" -eq 0 ] || return 2
    printf %s "$resp" |
      _normalizeJson |
      tr '{}' '\n' |
      grep -F "\"DomainName\":\"$1\"" |
      _egrep_o "arn:aws:acm:$2:[^\"]+" |
      grep "^arn:aws:acm:$2:"
    [ "$?" -eq 0 ] && return
    _token="$(printf %s "$resp" | _egrep_o '"NextToken": "[^"]+"')"
    _debug _token "$_token"
    if [ -z "$_token" ]; then
      return
    fi
    _next=${_token:14:-1}
  done
}
