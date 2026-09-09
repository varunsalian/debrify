FROM dart:3.12.2-sdk@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348
WORKDIR /work
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY lib ./lib
COPY worker.dart ./worker.dart
RUN dart analyze --fatal-infos worker.dart && dart compile exe worker.dart -o /work/stress
ENTRYPOINT ["/work/stress"]
