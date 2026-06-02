class_name BackendHttp
extends RefCounted

## The wire protocol for the Flask backend — header construction, JSON
## serialization, request dispatch, completion await, and response parsing — in
## ONE place. Callers supply their own HTTPRequest node (so each keeps its own
## concurrency policy: PlayerManager's single serialized loader, SaveManager's
## 8-slot pool, NetworkManager's per-call spawn) and their own retry / fallback
## policy. This module owns only what every caller does identically: how bytes
## go on the wire and come back off it.

## POSTs `payload` as JSON to `url` using the given HTTPRequest node and awaits
## the response. Returns:
##   { "started": bool, "result": int, "code": int, "body": String, "json": Variant }
## - started == false → http.request() never dispatched (connection-layer error
##   at send time); other fields are zero/empty. Caller should treat as offline.
## - started == true  → `result` is the HTTPRequest.Result (RESULT_SUCCESS on a
##   completed round-trip, else a transport failure like a timeout); `code` is the
##   HTTP status; `body` is the raw response text; `json` is the parsed body
##   (Dictionary / Array) or null if the body was empty / not valid JSON.
static func post_json(http: HTTPRequest, url: String, payload: Dictionary) -> Dictionary:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var request_body: String = JSON.stringify(payload)
	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, request_body)
	if err != OK:
		return {"started": false, "result": -1, "code": 0, "body": "", "json": null}

	var result: Array = await http.request_completed
	var text: String = result[3].get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	return {"started": true, "result": result[0], "code": result[1], "body": text, "json": parsed}
