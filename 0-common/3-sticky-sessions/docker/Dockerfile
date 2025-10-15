FROM tomee:10.1.0-Temurin-ubuntu-plus

# install additional tools "unzip"
RUN apt-get update && apt-get install unzip

# Sometimes fetching doesn't work. A manual downloaded local WAR could be copied into the container instead.
COPY src/StickySession.war /usr/local/tomee/webapps/

# unzip the Access Server WAR
RUN unzip /usr/local/tomee/webapps/StickySession.war -d /usr/local/tomee/webapps/

# remove configuration from WAR so that Docker Compose can map config files into the container
RUN rm -f /usr/local/tomee/webapps/*war

# copy the config files
COPY src/server.xml /usr/local/tomee/conf/
COPY src/catalina.properties /usr/local/tomee/conf/

EXPOSE 8080