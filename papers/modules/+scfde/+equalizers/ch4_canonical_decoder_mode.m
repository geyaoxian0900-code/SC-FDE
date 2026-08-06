function mode = ch4_canonical_decoder_mode(mode)
mode = string(mode);
switch lower(mode)
    case "map"
        mode = "MAP";
    case {"logmap", "log-map"}
        mode = "Log-MAP";
    case {"maxlog", "max-log-map", "maxlogmap"}
        mode = "Max-Log-MAP";
    otherwise
        error("SCFDE:UnknownDecoder", ...
            "Unknown BCJR decoder mode: %s", mode);
end
end
