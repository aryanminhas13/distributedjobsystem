package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	otellog "go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	logSDK "go.opentelemetry.io/otel/sdk/log"
	metricSDK "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	traceSDK "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

var (
	jobTracer       = otel.Tracer("distributedjobsystem/jobs")
	requestCount    metric.Int64Counter
	requestLatency  metric.Float64Histogram
	jobsStarted     metric.Int64Counter
	jobsCompleted   metric.Int64Counter
	jobsRetried     metric.Int64Counter
	jobsFailed      metric.Int64Counter
	telemetryLogger otellog.Logger
)

func initTelemetry(ctx context.Context) (func(context.Context) error, error) {
	service := env("OTEL_SERVICE_NAME", "job-api")
	res, err := resource.Merge(
		resource.Default(),
		resource.NewSchemaless(attribute.String("service.name", service), attribute.String("deployment.environment", env("APP_ENV", "local"))),
	)
	if err != nil {
		return nil, err
	}
	shutdowns := []func(context.Context) error{}
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint != "" {
		if strings.EqualFold(os.Getenv("OTEL_EXPORTER_OTLP_PROTOCOL"), "grpc") {
			parsed, err := url.Parse(endpoint)
			if err != nil {
				return nil, err
			}
			host := parsed.Host
			if host == "" {
				host = parsed.Path
			}
			traceOptions := []otlptracegrpc.Option{otlptracegrpc.WithEndpoint(host)}
			metricOptions := []otlpmetricgrpc.Option{otlpmetricgrpc.WithEndpoint(host)}
			if parsed.Scheme == "http" || parsed.Scheme == "" {
				traceOptions = append(traceOptions, otlptracegrpc.WithInsecure())
				metricOptions = append(metricOptions, otlpmetricgrpc.WithInsecure())
			}
			traceExporter, err := otlptracegrpc.New(ctx, traceOptions...)
			if err != nil {
				return nil, err
			}
			tp := traceSDK.NewTracerProvider(traceSDK.WithBatcher(traceExporter), traceSDK.WithResource(res))
			otel.SetTracerProvider(tp)
			shutdowns = append(shutdowns, tp.Shutdown)
			metricExporter, err := otlpmetricgrpc.New(ctx, metricOptions...)
			if err != nil {
				return nil, err
			}
			mp := metricSDK.NewMeterProvider(metricSDK.WithReader(metricSDK.NewPeriodicReader(metricExporter, metricSDK.WithInterval(15*time.Second))), metricSDK.WithResource(res))
			otel.SetMeterProvider(mp)
			shutdowns = append(shutdowns, mp.Shutdown)
			logOptions := []otlploggrpc.Option{otlploggrpc.WithEndpoint(host)}
			if parsed.Scheme == "http" || parsed.Scheme == "" {
				logOptions = append(logOptions, otlploggrpc.WithInsecure())
			}
			logExporter, err := otlploggrpc.New(ctx, logOptions...)
			if err != nil {
				return nil, err
			}
			lp := logSDK.NewLoggerProvider(logSDK.WithProcessor(logSDK.NewBatchProcessor(logExporter)), logSDK.WithResource(res))
			global.SetLoggerProvider(lp)
			shutdowns = append(shutdowns, lp.Shutdown)
		} else {
			traceExporter, err := otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(strings.TrimRight(endpoint, "/")+"/v1/traces"))
			if err != nil {
				return nil, err
			}
			tp := traceSDK.NewTracerProvider(traceSDK.WithBatcher(traceExporter), traceSDK.WithResource(res))
			otel.SetTracerProvider(tp)
			shutdowns = append(shutdowns, tp.Shutdown)
			metricExporter, err := otlpmetrichttp.New(ctx, otlpmetrichttp.WithEndpointURL(strings.TrimRight(endpoint, "/")+"/v1/metrics"))
			if err != nil {
				return nil, err
			}
			mp := metricSDK.NewMeterProvider(metricSDK.WithReader(metricSDK.NewPeriodicReader(metricExporter, metricSDK.WithInterval(15*time.Second))), metricSDK.WithResource(res))
			otel.SetMeterProvider(mp)
			shutdowns = append(shutdowns, mp.Shutdown)
			logExporter, err := otlploghttp.New(ctx, otlploghttp.WithEndpointURL(strings.TrimRight(endpoint, "/")+"/v1/logs"))
			if err != nil {
				return nil, err
			}
			lp := logSDK.NewLoggerProvider(logSDK.WithProcessor(logSDK.NewBatchProcessor(logExporter)), logSDK.WithResource(res))
			global.SetLoggerProvider(lp)
			shutdowns = append(shutdowns, lp.Shutdown)
		}
	}
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
	jobTracer = otel.Tracer("distributedjobsystem/jobs")
	telemetryLogger = global.Logger("distributedjobsystem/http")
	meter := otel.Meter("distributedjobsystem")
	requestCount, _ = meter.Int64Counter("http.server.requests")
	requestLatency, _ = meter.Float64Histogram("http.server.duration", metric.WithUnit("ms"))
	jobsStarted, _ = meter.Int64Counter("jobs.started")
	jobsCompleted, _ = meter.Int64Counter("jobs.completed")
	jobsRetried, _ = meter.Int64Counter("jobs.retried")
	jobsFailed, _ = meter.Int64Counter("jobs.failed")
	return func(c context.Context) error {
		for i := len(shutdowns) - 1; i >= 0; i-- {
			if err := shutdowns[i](c); err != nil {
				return err
			}
		}
		return nil
	}, nil
}

type responseRecorder struct {
	http.ResponseWriter
	status int
}

func (w *responseRecorder) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func observabilityMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ws" {
			next.ServeHTTP(w, r)
			return
		}
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		ctx, span := jobTracer.Start(ctx, r.Method+" "+r.URL.Path, trace.WithSpanKind(trace.SpanKindServer))
		defer span.End()
		start := time.Now()
		rec := &responseRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r.WithContext(ctx))
		elapsed := float64(time.Since(start).Microseconds()) / 1000
		attrs := metric.WithAttributes(attribute.String("http.method", r.Method), attribute.String("http.route", r.URL.Path), attribute.Int("http.status_code", rec.status))
		requestCount.Add(ctx, 1, attrs)
		requestLatency.Record(ctx, elapsed, attrs)
		entry := map[string]any{"level": "INFO", "message": "http_request", "method": r.Method, "path": r.URL.Path, "status": rec.status, "duration_ms": elapsed, "trace_id": span.SpanContext().TraceID().String()}
		b, _ := json.Marshal(entry)
		log.Print(string(b))
		var record otellog.Record
		record.SetTimestamp(time.Now())
		record.SetSeverity(otellog.SeverityInfo)
		record.SetSeverityText("INFO")
		record.SetEventName("http.request")
		record.SetBody(attribute.StringValue("http_request"))
		record.AddAttributes(
			attribute.String("http.request.method", r.Method),
			attribute.String("url.path", r.URL.Path),
			attribute.Int("http.response.status_code", rec.status),
			attribute.Float64("http.server.request.duration_ms", elapsed),
		)
		telemetryLogger.Emit(ctx, record)
	})
}
