/**
 * IBus Sherpa ONNX engine process entry.
 *
 * {{{
 *   ./scripts/fetch-nemotron-model.sh
 *   ./build/ibus-engine-sherpa-onnx
 * }}}
 *
 * Model: ''~/.config/ibus-sherpa-onnx/model''. Prefs: ''settings.ini'' (KeyFile).
 * Toggle default: Ctrl+Shift+Space.
 * ''--debug'' / ''-d'': stderr + ~/.cache/ibus-sherpa-onnx/ibus-sherpa-onnx.debug.log.
 */
int main(string[] args)
{
	Gst.init(ref args);
	return new IBus.SherpaOnnx.Application().run(args);
}
