function phase = ch5_cck_phases(name, bits)
qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
switch name
    case {"FR-CCK", "GCCK-QPSK-8R"}
        phase = [qpsk(bits(1:2)), qpsk(bits(3:4)), ...
            qpsk(bits(5:6)), qpsk(bits(7:8))];
    case {"HR-CCK", "GCCK-QPSK-4R"}
        phase = [qpsk(bits(1:2)), pi * bits(3) + 0.5 * pi, 0, ...
            pi * bits(4)];
    case "GCCK-8PSK-12R"
        psk8 = @(triple) pi / 4 * ...
            (triple(1) + 2 * triple(2) + 4 * triple(3));
        phase = [psk8(bits(1:3)), psk8(bits(4:6)), ...
            psk8(bits(7:9)), psk8(bits(10:12))];
end
end
