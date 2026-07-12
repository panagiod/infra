# KubeShip — shipping management API (Go + Couchbase).
FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY static/ ./static/

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /kubeship ./cmd/kubeship

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /kubeship /kubeship

ENV PORT=8080
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/kubeship"]
