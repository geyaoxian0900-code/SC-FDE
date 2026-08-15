function receiver = ptr_dfe(channel, source, cfg)
%PTR_DFE Passive time-reversal (PTR) front end + known DFE (book (2-47)).
%   r_hat(t) = sum_p h_p*(-t) * r_p(t)   (LINEAR convolution per element)
%   D(t)     = sum_p h_p*(-t) * h_p(t)   (per-element autocorrelation sum)
%   The focused output is delay-aligned to the main tap of each
%   time-reversed filter (position L_b = numel of the active impulse)
%   and fed into the known-channel Wiener DFE (2-6)~(2-11) driven by
%   the equivalent channel D(t).
%   Single-branch fallback when the channel has no multi-element branch
%   data (the scenario default).  The previous circular (frequency-
%   domain) front end is kept in ptr_circular_engineering.m.
branches = [];
branchImpulses = [];
if isfield(channel, "branches") && ~isempty(channel.branches)
    branches = channel.branches;
end
if isfield(channel, "branchImpulses") && ~isempty(channel.branchImpulses)
    branchImpulses = channel.branchImpulses;
end
N = numel(channel.received);
if isempty(branches) || size(branches, 1) < 2 || ...
        isempty(branchImpulses) || size(branchImpulses, 1) < 2
    % Single-branch path (the original (2-47) single-element form).
    impulse = channel.impulse(:).';
    % Trim the zero-padded N-long impulse to its active span so the
    % matched filter and the equivalent channel keep a compact length:
    % the known-DFE MMSE target sits at the equivalent-channel main tap,
    % and with the N zero-padding that tap lands at index ~N/2 while the
    % solver only allows a delay of feedforwardTaps-1, putting the target
    % in the zero guard region (BER ~ 0.5).
    nzFirst = find(abs(impulse) > 0, 1, "first");
    nzLast = find(abs(impulse) > 0, 1, "last");
    impulseShort = impulse(nzFirst:nzLast);
    timeReversal = conj(fliplr(impulseShort));        % h*(-n)
    ptrFrontEndFull = conv(timeReversal, channel.received);
    % Matched-filter peak alignment: the main tap of h*(-n) (conj(h_0))
    % lands at output position L = numel(h), aligned with r(0); the DFE
    % stage then treats that tap as delay 0.
    L = numel(impulseShort);
    ptrFrontEnd = ptrFrontEndFull(L:L + N - 1);
    equivalent = conv(timeReversal, impulseShort);    % Q(t) = h*(-t)*h(t)
    elementCount = 1;
else
    % Multi-element (2-47) sum: one focused stream from all elements,
    % equivalent channel = sum of per-element autocorrelations.
    elementCount = size(branches, 1);
    ptrFrontEnd = zeros(1, N);
    equivalent = [];
    for elementIndex = 1:elementCount
        impEl = branchImpulses(elementIndex, :);
        nzFirst = find(abs(impEl) > 0, 1, "first");
        nzLast = find(abs(impEl) > 0, 1, "last");
        if isempty(nzFirst)
            impEl = channel.impulse(:).';
            nzFirst = find(abs(impEl) > 0, 1, "first");
            nzLast = find(abs(impEl) > 0, 1, "last");
        end
        impulseShort = impEl(nzFirst:nzLast);
        timeReversal = conj(fliplr(impulseShort));
        Lb = numel(impulseShort);
        focused = conv(timeReversal, branches(elementIndex, :));
        ptrFrontEnd = ptrFrontEnd + focused(Lb:Lb + N - 1);
        eqEl = conv(timeReversal, impulseShort);
        if isempty(equivalent)
            equivalent = zeros(1, numel(eqEl));
        elseif numel(eqEl) > numel(equivalent)
            equivalent = [equivalent, zeros(1, numel(eqEl) - numel(equivalent))];
        end
        equivalent(1:numel(eqEl)) = equivalent(1:numel(eqEl)) + eqEl;
    end
end
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    ptrFrontEnd, source.tx, equivalent, cfg);
trace.ptrElementCount = elementCount;
trace.ptrStructure = "(2-47) sum_p h_p*(-t) * r_p(t); D(t) = sum_p h_p*(-t) * h_p(t)";
trace.formulaStatus = "BOOK-EXACT";
receiver = scfde.equalizers.pack_equalizer("Passive TR-DFE", "ptr-dfe", ...
    decisions, mse, ptrFrontEnd, trace);
end
