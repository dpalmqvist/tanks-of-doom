# Tanks of Doom relay server.
#   docker build -t tanks-relay .
#   docker run -p 8080:8080 tanks-relay
FROM swift:6.0-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product TanksRelay --static-swift-stdlib

FROM ubuntu:jammy
RUN useradd --system relay
COPY --from=build /src/.build/release/TanksRelay /usr/local/bin/TanksRelay
USER relay
ENV PORT=8080
EXPOSE 8080
CMD ["TanksRelay"]
