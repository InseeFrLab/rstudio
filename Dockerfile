FROM rocker/geospatial:4.2.0

USER root

ARG SPARK_VERSION=3.2.0
ARG HADOOP_VERSION=3.3.1
ARG HIVE_VERSION=2.3.9

ARG HADOOP_URL="https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}"
ARG HADOOP_AWS_URL="https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws"
ARG HIVE_URL="https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}"
ARG SPARK_BUILD="spark-${SPARK_VERSION}-bin-hadoop-${HADOOP_VERSION}-hive-${HIVE_VERSION}"
ARG S3_BUCKET="https://minio.lab.sspcloud.fr/projet-onyxia/spark-build"

ENV HADOOP_HOME="/opt/hadoop"
ENV SPARK_HOME="/opt/spark"
ENV HIVE_HOME="/opt/hive"

# Install common softwares
RUN apt-get -y update && \ 
    curl -s https://raw.githubusercontent.com/InseeFrLab/onyxia/main/resources/common-software-docker-images.sh | bash -s && \
    apt-get -y install tini openjdk-11-jre-headless && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p $HADOOP_HOME $SPARK_HOME $HIVE_HOME

RUN cd /tmp \
    && wget ${HADOOP_URL}/hadoop-${HADOOP_VERSION}.tar.gz \
    && tar xzf hadoop-${HADOOP_VERSION}.tar.gz -C ${HADOOP_HOME} --owner root --group root --no-same-owner --strip-components=1 \
    && wget ${HADOOP_AWS_URL}/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar \
    && mkdir -p ${HADOOP_HOME}/share/lib/common/lib \
    && mv hadoop-aws-${HADOOP_VERSION}.jar ${HADOOP_HOME}/share/lib/common/lib \
    && wget ${S3_BUCKET}/${SPARK_BUILD}.tgz \
    && tar xzf ${SPARK_BUILD}.tgz -C $SPARK_HOME --owner root --group root --no-same-owner --strip-components=1 \
    && wget ${HIVE_URL}/apache-hive-${HIVE_VERSION}-bin.tar.gz \
    && tar xzf apache-hive-${HIVE_VERSION}-bin.tar.gz -C ${HIVE_HOME} --owner root --group root --no-same-owner --strip-components=1 \
    && wget https://jdbc.postgresql.org/download/postgresql-42.2.18.jar \
    && mv postgresql-42.2.18.jar ${HIVE_HOME}/lib/postgresql-jdbc.jar \
    && rm ${HIVE_HOME}/lib/guava-14.0.1.jar \
    && cp ${HADOOP_HOME}/share/hadoop/common/lib/guava-27.0-jre.jar ${HIVE_HOME}/lib/ \
    && wget https://repo1.maven.org/maven2/jline/jline/2.14.6/jline-2.14.6.jar \
    && mv jline-2.14.6.jar ${HIVE_HOME}/lib/ \
    && rm ${HIVE_HOME}/lib/jline-2.12.jar \
    && rm -rf /tmp/*

ADD spark-env.sh $SPARK_HOME/conf
ADD entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh $SPARK_HOME/conf/spark-env.sh

ENV PYTHONPATH="$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.2-src.zip"
ENV SPARK_OPTS --driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M
ENV JAVA_HOME "/usr/lib/jvm/java-11-openjdk-amd64"
ENV HADOOP_OPTIONAL_TOOLS "hadoop-aws"
ENV PATH="${JAVA_HOME}/bin:${SPARK_HOME}/bin:${HADOOP_HOME}/bin:${PATH}"

ENV \
    # Change the locale
    LANG=fr_FR.UTF-8 \
    # option for include s3 support in arrow package
    LIBARROW_MINIMAL=false


RUN \
    # Add Shiny support
    bash /rocker_scripts/install_shiny_server.sh \
    # Install system librairies
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apt-utils software-properties-common \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-client \
        libpng++-dev \
        libudunits2-dev \
        libgdal-dev \
        curl \
        jq \
        bash-completion \
        gnupg2 \
        unixodbc \
        unixodbc-dev \
        odbc-postgresql \
        libsqliteodbc \
        alien \
        libsodium-dev \
        libsecret-1-dev \
        libarchive-dev \
        libglpk-dev \
#        chromium \
        ghostscript \
        fontconfig \
        fonts-symbola \
        fonts-noto \
        fonts-freefont-ttf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # Handle localization
    && cp /usr/share/zoneinfo/Europe/Paris /etc/localtime \
    && sed -i -e 's/# fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen \
    && dpkg-reconfigure --frontend=noninteractive locales \
    && update-locale LANG=fr_FR.UTF-8

RUN kubectl completion bash >/etc/bash_completion.d/kubectl

RUN \
    R -e "update.packages(ask = 'no')" \
    && install2.r --error \
        RPostgreSQL \
        RSQLite \
        odbc \
        keyring \
        aws.s3 \
        Rglpk \
        paws \
        vaultr \
	    arrow \
    && installGithub.r \
        inseeFrLab/doremifasol \
        `# pkgs for PROPRE reproducible publications:` \
        rstudio/pagedown \
        spyrales/gouvdown \
        spyrales/gouvdown.fonts \
    && R -e "devtools::install_github('apache/spark@v$SPARK_VERSION', subdir='R/pkg')" \
    && find /usr/local/lib/R/site-library/gouvdown.fonts -name "*.ttf" -exec cp '{}' /usr/local/share/fonts \; \
    && fc-cache \
    && Rscript -e "gouvdown::check_fonts_in_r()"

VOLUME ["/home"]
ENTRYPOINT [ "/opt/entrypoint.sh" ]
