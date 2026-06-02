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
##   { "started": bool, "code": int, "json": Variant }
## - started == false → http.request() never dispatched (connection-layer error);
##   `code` is 0 and `json` is null. Caller should treat this as offline.
## - started == true  → `code` is the HTTP status; `json` is the parsed body
##   (Dictionary / Array) or null if the body was empty / not valid JSON.
static func post_json(http: HTTPRequest, url: String, payload: Dictionary) -> Dictionary:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body: String = JSON.stringify(payload)
	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"started": false, "code": 0, "json": null}

	var result: Array = await http.request_completed
	var code: int = result[1]
	var response_body: PackedByteArray = result[3]
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	return {"started": true, "code": code, "json": parsed}
