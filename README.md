# Rails + Puma + Nginx + MySQL with Docker

將 Rails + Puma,  Nginx,  MySQL 都拆開成各自的 container，並透過 docker-compose 將多個 container 串起來，各司其職，協同服務。

* Nginx 在最前面解析請求並處理靜態資源
* Puma 位於 Nginx 於 Rails 程序之間，用於處理動態的請求；最後面還有一個數據存儲的 MySQL

container 分配

* app - 用來啟動 Rails + Puma
* web - 存放 nginx，負責解析各種外部請求，處理靜態的資源
(靜態資源就是運行 rake assets:precompile 生成在 public/assets 中的內容)
* db - MySQL

在現有的 rails project 加上 docker 所需的 file

```ruby
rails_project
├── docker
│   └── app
│       └── Dockerfile
│   └── db
│       └── grant_user.sql
│   └── web
│       ├── Dockerfile
│       └── nginx.conf
├── docker-compose.yml
└── .env
```


### docker/app/Dockerfile

```ruby
# Base image
FROM ruby:2.5.1

# Install plugin
RUN apt-get update -qq && apt-get install -y build-essential vim

# Install mysql
RUN apt-get install -y default-libmysqlclient-dev

# Install nodejs
RUN curl -sL https://deb.nodesource.com/setup_11.x | bash - &&\
    apt-get install -y nodejs

# Clears out the local repository of retrieved package files
RUN apt-get -q clean

# Set an environment variable where the Rails app is installed to inside of Docker image
ENV APP_PATH /usr/src/app
RUN mkdir -p $APP_PATH

# Set working directory
WORKDIR $APP_PATH

# Setting env up
ENV RAILS_ENV production
ENV RACK_ENV production
# Setting local
ENV LC_ALL C.UTF-8
# Setting timezone
ENV TZ Asia/Taipei
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# COPY Gemfile & Gemfil.lock
COPY Gemfile* $APP_PATH/

# Run bundle
RUN bundle install --jobs 20 --retry 5 --without development test --path vendor/bundle

# Adding project files
COPY . $APP_PATH/

# Build Frond-End
RUN RAILS_ENV=$RAILS_ENV bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### docker/web/Dockerfile

```ruby
# Base image
FROM nginx:1.15.8

# Install dependencies
RUN apt-get update -qq && apt-get -y install apache2-utils vim

# Establish where Nginx should look for files
ENV RAILS_ROOT /usr/src/app
# Setting local
ENV LC_ALL C.UTF-8
# Setting timezone
ENV TZ Asia/Taipei
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Set our working directory inside the image
WORKDIR $RAILS_ROOT

# create log directory
RUN mkdir log

# copy over static assets
COPY public public/

# Copy Nginx config template
COPY docker/web/nginx.conf /tmp/docker.nginx

# substitute variable references in the Nginx config template for real values from the environment
# put the final config in its place
RUN envsubst '$RAILS_ROOT' < /tmp/docker.nginx > /etc/nginx/conf.d/default.conf
EXPOSE 80

# Use the "exec" form of CMD so Nginx shuts down gracefully on SIGTERM (i.e. `docker stop`)
CMD [ "nginx", "-g", "daemon off;" ]
```

### docker/web/nginx.conf

```ruby
# define our application server

upstream rails_app {
  # The app service 3000 port that points to the docker-compose definition
   server app:3000;
}

server {
   listen 80;
   # define your domain or IP
   server_name localhost;

   # define the public application root
   root   $RAILS_ROOT/public;
   index  index.html;

   # define where Nginx should write its logs
   access_log $RAILS_ROOT/log/nginx.access.log;
   error_log $RAILS_ROOT/log/nginx.error.log;

   # deny requests for files that should never be accessed
   # ~ regular 區分大小寫, .env / .git
   location ~ /\. {
      deny all;
   }

   # ~* regular 不分大小寫, .rb / .log
   location ~* ^.+\.(rb|log)$ {
      deny all;
   }

   # serve static (compiled) assets directly if they exist (for rails production)
   location ~ ^/(assets|images|javascripts|stylesheets|swfs|system)/   {
      # $uri: localhost/404.html，則 $uri 為 `/404.html`
      # @rails: 後面定義的 location @rails
      # 如果 url 匹配進來，則先按 $uri 處理，若沒有找到，則交給 @rails 處理
      try_files $uri @rails;
      # close access log
      access_log off;
      # to serve pre-gzipped version
      # 設定為 `on` ，在處理壓縮之前，先查找已經預壓縮的文件（.gz）
      # 避免每次對同一個文件進行重複的壓縮處理
      gzip_static on;

      expires max;
      # public 對每個用戶有效; private 對當前用戶有效
      add_header Cache-Control public;

      add_header Last-Modified "";
      add_header ETag "";
      break;
   }

   # send non-static file requests to the app server
   location / {
      try_files $uri @rails;
   }

   location @rails {
      internal; # 只能被內部的請求呼叫，外部的呼叫請求會返回 'Not found'
      proxy_set_header  X-Real-IP  $remote_addr;
      proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Host $http_host;
      proxy_redirect off;
      proxy_pass http://rails_app; # 導向到 upstream rails_app
   }
}
```

### database.yml

`host name` 必須對應到 docker-compose 所定義的 `service name`，並且透過環境變數所設定的 user 來登入

```ruby
default: &default
  adapter: mysql2
  encoding: utf8
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: db
  port: 3306
  username: <%= ENV.fetch('MYSQL_USER') { 'root' } %>
  password: <%= ENV.fetch('MYSQL_PASSWORD') { 'password' } %>
  socket: /tmp/mysql.sock
```

### docker/db/grant_user.sql

因為在 mysql 有另外建立一個 user，並且在 database.yml 也是透過這個 user 來登入，因此必須授權給此 user 權限，才能夠操作

```ruby
GRANT ALL PRIVILEGES ON *.* TO 'user_name'@'%';
FLUSH PRIVILEGES;
```

### docker-compose.yml

```ruby
version: '3'
services:
  app:
    build:
      context: .
      dockerfile: ./docker/app/Dockerfile
    env_file:
      - .env
    volumes:
      - .:/usr/src/app
    depends_on:
      - db
  db:
    image: mysql:5.7.23
    command: --default-authentication-plugin=mysql_native_password
    restart: always
    env_file:
      - .env
    ports:
      - "3306:3306"
    volumes:
      - db-data:/var/lib/mysql
  web:
    build:
      context: .
      dockerfile: ./docker/web/Dockerfile
    ports:
      - 80:80
    depends_on:
      - app
volumes:
  db-data:
    external: false
```

### .env

docker-compose 所需要用到的環境變數，app & web 都會用到

```ruby
MYSQL_ROOT_PASSWORD=password
MYSQL_USER=user_name
MYSQL_PASSWORD=user_password
```

### Example project

[product_system_production](https://github.com/mgleon08/product_system_production)

```ruby
git clone https://github.com/mgleon08/product_system_production
# 建立 image
docker-compose build
# 啟動
docker-compose up -d
# 因為是建立新的 user 來造訪 mysql，因此必須先授權此 user 權限
p# 確認是否授權成功
docker-compose exec db mysql -u user_name -p -e"show grants;"
# 建立資料庫
docker-compose run --rm app bundle exec rails db:create
# 跑 migrate
docker-compose run --rm app bundle exec rails db:migrate
# 建立假資料
docker-compose run --rm app bundle exec rails db:seed
# 查看畫面, 記得是 http
http://localhost
```

### Production

Rails5.2 之後，secret_key_base 的設定改了，在 production 上要在 config 裡面加上 master.key file，並將 local 的亂數貼上去

* [Rails 5.2 Credentials](https://mgleon08.github.io/blog/2018/07/14/rails-credentials/)
* [Rails 5.2: encrypted secrets](https://keithpblog.org/post/encrypted-secrets/)

參考文件:

* [Docker + Rails + Puma + Nginx + MySQL](https://qiita.com/eighty8/items/0288ab9c127ddb683315#db%E6%8E%A5%E7%B6%9A%E7%94%A8%E3%81%AE%E6%83%85%E5%A0%B1%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB)
* [Docker + Rails + Puma + Nginx + Postgres](https://itnext.io/docker-rails-puma-nginx-postgres-999cd8866b18)
* [config.assets.compile=true in Rails production, why not?](https://stackoverflow.com/questions/8821864/config-assets-compile-true-in-rails-production-why-not/8827757#8827757)
* [Docker for an Existing Rails Application](http://chrisstump.online/2016/02/20/docker-existing-rails-application/)
* [What does upstream mean in nginx?](https://stackoverflow.com/questions/5877929/what-does-upstream-mean-in-nginx)
* [SQL GRANT 授與資料庫使用權限](https://www.fooish.com/sql/grant-privileges.html)
* [nginx 基礎設定教學](https://blog.hellojcc.tw/2015/12/07/nginx-beginner-tutorial/)
