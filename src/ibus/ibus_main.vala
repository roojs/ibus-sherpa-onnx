/**
 * IBus Speech STT engine process entry.
 *
 * {{{
 *   mkdir -p ~/.config/stt-ibus
 *   ln -sfn "$PWD/models/sherpa-onnx-nemotron-…" ~/.config/stt-ibus/model
 *   ./build/stt-ibus-engine
 * }}}
 *
 * ''~/.config/stt-ibus/model'' is a directory or symlink to the ASR model.
 * Toggle: Ctrl+Shift+Space or ''~/.config/stt-ibus/hotkey''.
 * ''--debug'' / ''-d'': stderr + ~/.cache/stt-ibus/stt-ibus-engine.debug.log.
 */
int main(string[] args)
{
	Gst.init(ref args);
	return new SttPoc.SttIbusApplication().run(args);
}
