function root = csk_root_sequence(lengthCode, family)
switch lower(string(family))
    case "m-sequence"
        % The degree-6 recurrence in (6-1) provides the PN root; longer
        % spreading factors repeat its complete 63-chip period.
        period = scfde.equalizers.ch6_m_sequence63(1);
        root = period(mod(0:lengthCode - 1, numel(period)) + 1);
    case "optimized-pn"
        root = scfde.equalizers.ch6_select_csk_root(lengthCode);
    otherwise
        error("SCFDE:UnknownCskRoot", ...
            "cskRootFamily must be m-sequence or optimized-pn.");
end
root = root / norm(root);
end