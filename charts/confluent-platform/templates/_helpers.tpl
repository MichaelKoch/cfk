{{/* Image reference for a Confluent Platform component. */}}
{{- define "cp.image" -}}
image:
  application: confluentinc/{{ .name }}:{{ .root.Values.platform.version }}
  init: {{ .root.Values.platform.initImage }}
{{- end }}

{{/* Fully qualified in-cluster URL of a component service. */}}
{{- define "cp.url" -}}
http://{{ .name }}.{{ .root.Release.Namespace }}.svc.cluster.local:{{ .port }}
{{- end }}

{{/* Settings shared by every component: storage class and pod resources. */}}
{{- define "cp.common" -}}
storageClass:
  name: {{ .root.Values.platform.storageClass }}
podTemplate:
  resources:
    {{- toYaml .component.resources | nindent 4 }}
{{- end }}

{{/* Kafka/KRaft metrics are pushed to the Control Center Prometheus. */}}
{{- define "cp.metricsClient" -}}
{{- if .Values.controlCenter.enabled -}}
metricsClient:
  url: {{ include "cp.url" (dict "root" . "name" "controlcenter" "port" 9090) }}
{{- end }}
{{- end }}

{{/* FlinkEnvironment name: unique across the shared CMF, defaults to the release namespace. */}}
{{- define "cp.flinkEnvironment" -}}
{{ .Values.flink.environment | default .Release.Namespace }}
{{- end }}

{{/* SQL Gateway extra jars (Flink 2.x images ship no Kafka connector): an init container downloads
     sqlGateway.extraJars into an emptyDir, each jar is mounted into /opt/flink/lib. */}}
{{- define "cp.sqlGatewayJars.initContainers" -}}
{{- with .Values.sqlGateway.extraJars }}
initContainers:
  - name: fetch-jars
    image: {{ $.Values.sqlGateway.jarLoaderImage }}
    command: ["sh", "-c"]
    args:
      - |
        set -e
        {{- range . }}
        curl -fsSL -o /jars/{{ base . }} {{ . }}
        {{- end }}
    volumeMounts:
      - { name: extra-jars, mountPath: /jars }
{{- end }}
{{- end }}

{{- define "cp.sqlGatewayJars.volumes" -}}
{{- if .Values.sqlGateway.extraJars }}
volumes:
  - { name: extra-jars, emptyDir: {} }
{{- end }}
{{- end }}

{{- define "cp.sqlGatewayJars.volumeMounts" -}}
{{- with .Values.sqlGateway.extraJars }}
volumeMounts:
  {{- range . }}
  - { name: extra-jars, mountPath: /opt/flink/lib/{{ base . }}, subPath: {{ base . }} }
  {{- end }}
{{- end }}
{{- end }}
