# kube-bench Job template — benchmark substituted by scripts/run-kube-bench.sh
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: kube-system
  labels:
    app.kubernetes.io/name: kube-bench
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kube-bench
    spec:
      hostPID: true
      restartPolicy: Never
      tolerations:
        - operator: Exists
      containers:
        - name: kube-bench
          image: docker.io/aquasec/kube-bench:v0.7.1
          command:
            - kube-bench
            - run
            - --benchmark
            - BENCHMARK
          securityContext:
            privileged: true
          volumeMounts:
            - name: var-lib-kubelet
              mountPath: /var/lib/kubelet
              readOnly: true
            - name: etc-systemd
              mountPath: /etc/systemd
              readOnly: true
            - name: etc-kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
      volumes:
        - name: var-lib-kubelet
          hostPath:
            path: /var/lib/kubelet
        - name: etc-systemd
          hostPath:
            path: /etc/systemd
        - name: etc-kubernetes
          hostPath:
            path: /etc/kubernetes
