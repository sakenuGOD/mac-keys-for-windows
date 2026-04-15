; Minimal JSON parser and stringifier for AutoHotkey v2.
; Supports: null, true, false, numbers, strings (with \n \t \" \\ \/ \b \f \r \uXXXX),
; arrays -> Array, objects -> Map (ordered by insertion).

class Json {
    static Parse(text) {
        pos := 1
        Json._SkipWs(&text, &pos)
        value := Json._ParseValue(&text, &pos)
        Json._SkipWs(&text, &pos)
        return value
    }

    static Stringify(value, indent := "") {
        return Json._Stringify(value, indent, "")
    }

    static _ParseValue(&t, &p) {
        Json._SkipWs(&t, &p)
        c := SubStr(t, p, 1)
        if c = "{"
            return Json._ParseObject(&t, &p)
        if c = "["
            return Json._ParseArray(&t, &p)
        if c = '"'
            return Json._ParseString(&t, &p)
        if c = "t" || c = "f"
            return Json._ParseBool(&t, &p)
        if c = "n" {
            if SubStr(t, p, 4) = "null" {
                p += 4
                return ""
            }
            throw Error("Invalid literal at " p)
        }
        return Json._ParseNumber(&t, &p)
    }

    static _ParseObject(&t, &p) {
        m := Map()
        p += 1
        Json._SkipWs(&t, &p)
        if SubStr(t, p, 1) = "}" {
            p += 1
            return m
        }
        loop {
            Json._SkipWs(&t, &p)
            if SubStr(t, p, 1) != '"'
                throw Error("Expected string key at " p)
            key := Json._ParseString(&t, &p)
            Json._SkipWs(&t, &p)
            if SubStr(t, p, 1) != ":"
                throw Error("Expected ':' at " p)
            p += 1
            m[key] := Json._ParseValue(&t, &p)
            Json._SkipWs(&t, &p)
            c := SubStr(t, p, 1)
            if c = "," {
                p += 1
                continue
            }
            if c = "}" {
                p += 1
                return m
            }
            throw Error("Expected ',' or '}' at " p)
        }
    }

    static _ParseArray(&t, &p) {
        a := []
        p += 1
        Json._SkipWs(&t, &p)
        if SubStr(t, p, 1) = "]" {
            p += 1
            return a
        }
        loop {
            a.Push(Json._ParseValue(&t, &p))
            Json._SkipWs(&t, &p)
            c := SubStr(t, p, 1)
            if c = "," {
                p += 1
                continue
            }
            if c = "]" {
                p += 1
                return a
            }
            throw Error("Expected ',' or ']' at " p)
        }
    }

    static _ParseString(&t, &p) {
        p += 1
        out := ""
        loop {
            c := SubStr(t, p, 1)
            if c = ""
                throw Error("Unterminated string")
            if c = '"' {
                p += 1
                return out
            }
            if c = "\" {
                esc := SubStr(t, p + 1, 1)
                switch esc {
                    case '"': out .= '"'
                    case "\": out .= "\"
                    case "/": out .= "/"
                    case "b": out .= "`b"
                    case "f": out .= "`f"
                    case "n": out .= "`n"
                    case "r": out .= "`r"
                    case "t": out .= "`t"
                    case "u":
                        hex := SubStr(t, p + 2, 4)
                        out .= Chr(Integer("0x" hex))
                        p += 4
                    default:
                        throw Error("Bad escape \" esc)
                }
                p += 2
                continue
            }
            out .= c
            p += 1
        }
    }

    static _ParseNumber(&t, &p) {
        start := p
        if SubStr(t, p, 1) = "-"
            p += 1
        while p <= StrLen(t) && InStr("0123456789.eE+-", SubStr(t, p, 1))
            p += 1
        num := SubStr(t, start, p - start)
        return num + 0
    }

    static _ParseBool(&t, &p) {
        if SubStr(t, p, 4) = "true" {
            p += 4
            return true
        }
        if SubStr(t, p, 5) = "false" {
            p += 5
            return false
        }
        throw Error("Bad bool at " p)
    }

    static _SkipWs(&t, &p) {
        while p <= StrLen(t) {
            c := SubStr(t, p, 1)
            if c = " " || c = "`t" || c = "`n" || c = "`r"
                p += 1
            else
                break
        }
    }

    static _Stringify(v, indent, curIndent) {
        if v = "" && !IsObject(v)
            return "null"
        if v = true
            return "true"
        if v = false
            return "false"
        if IsNumber(v)
            return v . ""
        if v is String
            return Json._EscapeString(v)
        if v is Array {
            if v.Length = 0
                return "[]"
            parts := []
            newIndent := curIndent . indent
            for item in v
                parts.Push(Json._Stringify(item, indent, newIndent))
            if indent = ""
                return "[" . Json._Join(parts, ",") . "]"
            return "[`n" . newIndent . Json._Join(parts, ",`n" . newIndent) . "`n" . curIndent . "]"
        }
        if v is Map {
            keys := []
            for k in v
                keys.Push(k)
            if keys.Length = 0
                return "{}"
            parts := []
            newIndent := curIndent . indent
            for k in keys
                parts.Push(Json._EscapeString(k) . (indent = "" ? ":" : ": ") . Json._Stringify(v[k], indent, newIndent))
            if indent = ""
                return "{" . Json._Join(parts, ",") . "}"
            return "{`n" . newIndent . Json._Join(parts, ",`n" . newIndent) . "`n" . curIndent . "}"
        }
        throw Error("Cannot stringify type")
    }

    static _EscapeString(s) {
        out := '"'
        loop parse s {
            c := A_LoopField
            code := Ord(c)
            if c = '"'
                out .= '\"'
            else if c = "\"
                out .= "\\"
            else if code = 8
                out .= "\b"
            else if code = 9
                out .= "\t"
            else if code = 10
                out .= "\n"
            else if code = 12
                out .= "\f"
            else if code = 13
                out .= "\r"
            else if code < 32
                out .= Format("\u{:04x}", code)
            else
                out .= c
        }
        return out . '"'
    }

    static _Join(arr, sep) {
        out := ""
        first := true
        for s in arr {
            if first
                first := false
            else
                out .= sep
            out .= s
        }
        return out
    }
}
