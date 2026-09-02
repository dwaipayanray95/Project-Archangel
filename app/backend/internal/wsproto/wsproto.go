// Package wsproto defines the JSON frame shapes used on Archangel's
// WebSocket endpoints (terminal now, stats streaming later). Every frame is
// a small JSON object with a "type" field that says which of the fields
// below actually apply - callers switch on Type.
package wsproto

// Frame is sent in both directions. Not every field is used by every Type;
// see the comments below for which fields apply to which type.
type Frame struct {
	Type string `json:"type"`

	// "stdin" (client->server) / "stdout" (server->client): base64-encoded
	// raw bytes. Base64+JSON is slightly wasteful over the wire compared to
	// binary WS frames, but it's far easier to read in browser dev tools
	// and Go tests while this is being built - worth optimizing later only
	// if it's actually a bottleneck.
	Data string `json:"data,omitempty"`

	// "resize" (client->server): new terminal size.
	Cols int `json:"cols,omitempty"`
	Rows int `json:"rows,omitempty"`

	// "exit" (server->client): the shell process's exit code.
	Code int `json:"code,omitempty"`

	// "error" (server->client): human-readable message.
	Message string `json:"message,omitempty"`
}

const (
	TypeStdin  = "stdin"
	TypeStdout = "stdout"
	TypeResize = "resize"
	TypePing   = "ping"
	TypePong   = "pong"
	TypeExit   = "exit"
	TypeError  = "error"
)
