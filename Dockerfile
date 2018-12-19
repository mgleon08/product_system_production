FROM ruby:2.5.1

RUN apt-get update -qq &&\
    curl -sL https://deb.nodesource.com/setup_11.x | bash - &&\
    apt-get install -y nodejs cmake &&\
    apt-get clean

ARG UID
RUN adduser deploy --uid $UID --disabled-password --gecos ""

ENV APP /usr/src/app
RUN mkdir $APP
WORKDIR $APP

COPY Gemfile* $APP/
RUN bundle install -j3 --path vendor/bundle

COPY . $APP/

CMD ["bundle", "exec", "rails", "server", "-p", "3000", "-b", "0.0.0.0"]
