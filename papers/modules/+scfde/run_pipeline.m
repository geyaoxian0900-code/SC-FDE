function result = run_pipeline(cfg, modules)
%RUN_PIPELINE Execute a source-channel-receiver-metric module chain.

source = modules.source(cfg);
channel = modules.channel(source.tx, cfg);
receiver = modules.receiverBank(channel, source, cfg);
metrics = modules.metric(receiver, source, cfg);

result.config = cfg;
result.modules = modules;
result.source = source;
result.channel = channel;
result.receiver = receiver;
result.metrics = metrics;
end
