#!/bin/zsh
set -x
#git stash
git pull || exit 3
setopt PUSHDSILENT
update_plugins() {
  pushd plugins
  for my_link in *; do
    echo $my_link
  if [ -L ${my_link} ] ; then
    if [ -e ${my_link} ] ; then
    #    echo "Good link"
        pushd ${my_link}
        yes|git pull
        popd
    else
        : #echo "Broken link"
    fi
  elif [ -e ${my_link} ] ; then
    : #echo "Not a link"
  else
    : #echo "Missing"
  fi
  done
  popd
}
# set yarn version to classic, otherwise, will have this error:
# Duplicate workspace name discourse: /f/discourse/app/assets/javascripts/discourse conflicts with /f/discourse
#bundle install && yarn set version classic && yarn install && bin/rails db:migrate
bundle install && pnpm install && bin/rails db:migrate

#bin/ember-cli serve
bin/ember-cli -u
#ALLOW_EMBER_CLI_PROXY_BYPASS=1 DISCOURSE_DEV_LOG_LEVEL=warn RAILS_DEVELOPMENT_HOSTS=xjtu.men bin/rails s

