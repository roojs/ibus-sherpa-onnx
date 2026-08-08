[CCode (cheader_filename = "sherpa-onnx/c-api/c-api.h", cprefix = "SherpaOnnx", lower_case_cprefix = "SherpaOnnx")]
namespace SherpaOnnx
{
	[CCode (cname = "SherpaOnnxOnlineTransducerModelConfig", has_type_id = false)]
	public struct OnlineTransducerModelConfig
	{
		public unowned string? encoder;
		public unowned string? decoder;
		public unowned string? joiner;
	}

	[CCode (cname = "SherpaOnnxOnlineParaformerModelConfig", has_type_id = false)]
	public struct OnlineParaformerModelConfig
	{
		public unowned string? encoder;
		public unowned string? decoder;
	}

	[CCode (cname = "SherpaOnnxOnlineZipformer2CtcModelConfig", has_type_id = false)]
	public struct OnlineZipformer2CtcModelConfig
	{
		public unowned string? model;
	}

	[CCode (cname = "SherpaOnnxOnlineNemoCtcModelConfig", has_type_id = false)]
	public struct OnlineNemoCtcModelConfig
	{
		public unowned string? model;
	}

	[CCode (cname = "SherpaOnnxOnlineToneCtcModelConfig", has_type_id = false)]
	public struct OnlineToneCtcModelConfig
	{
		public unowned string? model;
	}

	[CCode (cname = "SherpaOnnxOnlineModelConfig", has_type_id = false)]
	public struct OnlineModelConfig
	{
		public OnlineTransducerModelConfig transducer;
		public OnlineParaformerModelConfig paraformer;
		public OnlineZipformer2CtcModelConfig zipformer2_ctc;
		public unowned string? tokens;
		public int32 num_threads;
		public unowned string? provider;
		public int32 debug;
		public unowned string? model_type;
		public unowned string? modeling_unit;
		public unowned string? bpe_vocab;
		public unowned string? tokens_buf;
		public int32 tokens_buf_size;
		public OnlineNemoCtcModelConfig nemo_ctc;
		public OnlineToneCtcModelConfig t_one_ctc;
	}

	[CCode (cname = "SherpaOnnxFeatureConfig", has_type_id = false)]
	public struct FeatureConfig
	{
		public int32 sample_rate;
		public int32 feature_dim;
	}

	[CCode (cname = "SherpaOnnxOnlineCtcFstDecoderConfig", has_type_id = false)]
	public struct OnlineCtcFstDecoderConfig
	{
		public unowned string? graph;
		public int32 max_active;
	}

	[CCode (cname = "SherpaOnnxHomophoneReplacerConfig", has_type_id = false)]
	public struct HomophoneReplacerConfig
	{
		public unowned string? dict_dir;
		public unowned string? lexicon;
		public unowned string? rule_fsts;
	}

	[CCode (cname = "SherpaOnnxOnlineRecognizerConfig", has_type_id = false)]
	public struct OnlineRecognizerConfig
	{
		public FeatureConfig feat_config;
		public OnlineModelConfig model_config;
		public unowned string? decoding_method;
		public int32 max_active_paths;
		public int32 enable_endpoint;
		public float rule1_min_trailing_silence;
		public float rule2_min_trailing_silence;
		public float rule3_min_utterance_length;
		public unowned string? hotwords_file;
		public float hotwords_score;
		public OnlineCtcFstDecoderConfig ctc_fst_decoder_config;
		public unowned string? rule_fsts;
		public unowned string? rule_fars;
		public float blank_penalty;
		public unowned string? hotwords_buf;
		public int32 hotwords_buf_size;
		public HomophoneReplacerConfig hr;
	}

	[CCode (cname = "SherpaOnnxOnlineRecognizerResult", free_function = "SherpaOnnxDestroyOnlineRecognizerResult", has_type_id = false)]
	[Compact]
	public class OnlineRecognizerResult
	{
		[CCode (cname = "text")]
		unowned string? bound_text;

		/** Recognized text; never null (empty string if C pointer is NULL). */
		public unowned string text {
			get {
				return this.bound_text ?? "";
			}
		}

		public unowned string tokens;
		[CCode (array_length = false)]
		public unowned string? tokens_arr;
		[CCode (array_length_cname = "count")]
		public float[]? timestamps;
		public int32 count;
		public unowned string json;
	}

	[CCode (cname = "SherpaOnnxOnlineStream", free_function = "SherpaOnnxDestroyOnlineStream", has_type_id = false)]
	[Compact]
	public class OnlineStream
	{
		[CCode (cname = "SherpaOnnxOnlineStreamAcceptWaveform")]
		public void accept_waveform (int32 sample_rate, [CCode (array_length_cname = "n", array_length_pos = 2.5)] float[] samples);

		[CCode (cname = "SherpaOnnxOnlineStreamInputFinished")]
		public void input_finished ();

		[CCode (cname = "SherpaOnnxOnlineStreamSetOption")]
		public void set_option (string key, string value);
	}

	[CCode (cname = "SherpaOnnxOnlineRecognizer", free_function = "SherpaOnnxDestroyOnlineRecognizer", has_type_id = false)]
	[Compact]
	public class OnlineRecognizer
	{
		[CCode (cname = "SherpaOnnxCreateOnlineRecognizer")]
		public OnlineRecognizer (OnlineRecognizerConfig config);

		[CCode (cname = "SherpaOnnxCreateOnlineStream")]
		public OnlineStream create_stream ();

		[CCode (cname = "SherpaOnnxIsOnlineStreamReady")]
		public int32 is_ready (OnlineStream stream);

		[CCode (cname = "SherpaOnnxDecodeOnlineStream")]
		public void decode (OnlineStream stream);

		[CCode (cname = "SherpaOnnxGetOnlineStreamResult")]
		public OnlineRecognizerResult get_result (OnlineStream stream);

		[CCode (cname = "SherpaOnnxOnlineStreamIsEndpoint")]
		public int32 is_endpoint (OnlineStream stream);

		[CCode (cname = "SherpaOnnxOnlineStreamReset")]
		public void reset (OnlineStream stream);
	}
}
