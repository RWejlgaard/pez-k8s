import jsonpatch
import copy
import base64
from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route("/mutate", methods=["POST"])
def mutate():
    spec = request.json["request"]["object"]
    modified_spec = copy.deepcopy(spec)

    try:
        modified_spec["spec"]["hosts"][0] = str(modified_spec["spec"]["hosts"][0]).split('.')[0] + ".ovh.pez.sh"
        modified_spec["spec"]["gateways"][0] = "istio-system/ovh-pez-sh"
    except KeyError:
        pass

    patch = jsonpatch.JsonPatch.from_diff(spec, modified_spec)

    return jsonify(
        {
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {
                "allowed": True,
                "uid": request.json["request"]["uid"],
                "patch": base64.b64encode(str(patch).encode()).decode(),
                "patchType": "JSONPatch"
            }
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port="8443", debug=True, ssl_context=('/ssl/tls.crt', '/ssl/tls.key'))
