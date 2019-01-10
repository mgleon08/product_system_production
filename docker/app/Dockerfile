# Base image
FROM ruby:2.5.1

# Install plugin
RUN apt-get update -qq && apt-get install -y build-essential vim

# Install mysql
RUN apt-get install -y default-libmysqlclient-dev

# Install nodejs for JavaScript Runtime
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
RUN bundle install --jobs 20 --retry 5 --without development test

# Adding project files
COPY . $APP_PATH/

# Build Frond-End
RUN RAILS_ENV=$RAILS_ENV bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
