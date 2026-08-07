/**
 * IBus Sherpa ONNX engine process entry.
 *
 * {{{
 *   mkdir -p ~/.config/ibus-sherpa-onnx
 *   ln -sfn "$PWD/models/sherpa-onnx-nemotron-…" ~/.config/ibus-sherpa-onnx/model
 *   ./build/ibus-engine-sherpa-onnx
 * }}}
 *
 * ''~/.config/ibus-sherpa-onnx/model'' is a directory or symlink to the ASR model.
 * Toggle: Ctrl+Shift+Space or ''~/.config/ibus-sherpa-onnx/hotkey''.
 * ''--debug'' / ''-d'': stderr + ~/.cache/ibus-sherpa-onnx/ibus-sherpa-onnx.debug.log.
 */
int main(string[] args)
{
	Gst.init(ref args);
	return new IBus.SherpaOnnx.Application().run(args);
}
