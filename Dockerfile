# Base image
FROM ruby:2.6.5-alpine

# Setup environment variables that will be available to the instance
ENV APP_HOME /app
ENV LANG C.UTF-8
ENV GEM_HOME $APP_HOME/bundle
ENV BUNDLE_PATH $GEM_HOME
ENV BUNDLE_APP_CONFIG $BUNDLE_PATH
ENV BUNDLE_BIN $BUNDLE_PATH/bin
ENV BUNDLE_CACHE_ALL "true"

# Add bundle dir to path to be able to access commands outside of `bundle exec`
ENV PATH /app/bin:$BUNDLE_BIN:$PATH

RUN apk --no-cache add gcc libc-dev make \
  && rm -rf /var/cache/apk/* \
  && mkdir -p $APP_HOME
WORKDIR $APP_HOME
COPY Gemfile $APP_HOME
RUN bundle install -j2
ADD . $APP_HOME
