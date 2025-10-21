# FROM tomee:10.1.0-Temurin-ubuntu-plus

# # install additional tools "unzip"
# RUN apt-get update && apt-get install unzip

# # Sometimes fetching doesn't work. A manual downloaded local WAR could be copied into the container instead.
# COPY src/StickySession.war /usr/local/tomee/webapps/

# # unzip the Access Server WAR
# RUN unzip /usr/local/tomee/webapps/StickySession.war -d /usr/local/tomee/webapps/

# # remove configuration from WAR so that Docker Compose can map config files into the container
# RUN rm -f /usr/local/tomee/webapps/*war

# # copy the config files
# COPY src/server.xml /usr/local/tomee/conf/
# COPY src/catalina.properties /usr/local/tomee/conf/

# EXPOSE 8080

# ------------------------------------------------------------------------
# Use Alpine-based base image to decrease attack surface
FROM tomee:jre25-Temurin-alpine-plus

# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    unzip

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN addgroup -g 1001 tomee && \
    adduser -h /home/tomee -s /bin/sh -u 1001 -G tomee -D tomee

# Sometimes fetching doesn't work. A manual downloaded local WAR could be copied into the container instead.
COPY src/StickySession.war /usr/local/tomee/webapps/

# unzip the Access Server WAR
RUN unzip /usr/local/tomee/webapps/StickySession.war -d /usr/local/tomee/webapps/

# remove configuration from WAR so that Docker Compose can map config files into the container
RUN rm -f /usr/local/tomee/webapps/*war

# add OpenShift compatible permission sets
RUN chgrp -R 0 /home/tomee /usr/local/tomee/ && \
    chmod -R g=u /home/tomee /usr/local/tomee/ && \
    chmod -R g+rwx /usr/local/tomee/logs /usr/local/tomee/temp /usr/local/tomee/work

# copy the config files
COPY src/server.xml /usr/local/tomee/conf/
COPY src/catalina.properties /usr/local/tomee/conf/

USER tomee

EXPOSE 8080