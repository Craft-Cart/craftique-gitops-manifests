{{/*
Expand the name of the chart.
*/}}
{{- define "craftique-backend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "craftique-backend.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "craftique-backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (Kubernetes Recommended Labels)
*/}}
{{- define "craftique-backend.labels" -}}
helm.sh/chart: {{ include "craftique-backend.chart" . }}
{{ include "craftique-backend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- with .Values.governanceLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "craftique-backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "craftique-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: craftique-backend
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "craftique-backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "craftique-backend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image with registry
*/}}
{{- define "craftique-backend.image" -}}
{{- $tag := .Values.image.tag | default (printf "@sha256:%s" .Chart.AppVersion) }}
{{- printf "%s%s" .Values.image.repository $tag }}
{{- end }}
