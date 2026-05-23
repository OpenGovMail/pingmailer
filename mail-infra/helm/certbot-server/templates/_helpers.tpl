{{/*
Expand the name of the chart.
*/}}
{{- define "certbot-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "certbot-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version label.
*/}}
{{- define "certbot-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "certbot-server.labels" -}}
helm.sh/chart: {{ include "certbot-server.chart" . }}
{{ include "certbot-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "certbot-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "certbot-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the secret holding sensitive certbot env vars.
*/}}
{{- define "certbot-server.secretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "certbot-server.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Returns true when the chart should create its own secret (i.e. no
existingSecret was provided AND at least one .Values.secret.* key is non-empty).
*/}}
{{- define "certbot-server.shouldCreateSecret" -}}
{{- if .Values.existingSecret -}}
false
{{- else -}}
{{- $any := false -}}
{{- range $k, $v := .Values.secret -}}
{{- if $v -}}{{- $any = true -}}{{- end -}}
{{- end -}}
{{ $any }}
{{- end -}}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "certbot-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "certbot-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
