FROM openresty/openresty:1.29.2.1-alpine-fat

# opm (OpenResty Package Manager) でパッケージをインストール
# luarocks はマニフェストが LuaJIT の定数上限(65536)を超えるため使用不可
# lua-cjson は OpenResty に同梱済みのため不要
RUN opm get ledgetech/lua-resty-http \
             zmartzone/lua-resty-openidc && \
    # lua-resty-session 4.x は lua-resty-openidc 1.7.5 と非互換のため 3.10 を手動インストール
    wget -qO /tmp/session.tar.gz \
         https://github.com/bungle/lua-resty-session/archive/refs/tags/v3.10.tar.gz && \
    tar -xzf /tmp/session.tar.gz -C /tmp && \
    rm -rf /usr/local/openresty/site/lualib/resty/session && \
    cp /tmp/lua-resty-session-3.10/lib/resty/session.lua \
       /usr/local/openresty/site/lualib/resty/session.lua && \
    cp -r /tmp/lua-resty-session-3.10/lib/resty/session \
          /usr/local/openresty/site/lualib/resty/ && \
    rm -rf /tmp/session.tar.gz /tmp/lua-resty-session-3.10

# nginx設定はConfigMapからマウントされるため、デフォルト設定を削除
RUN rm -f /etc/nginx/conf.d/default.conf

EXPOSE 80 443
