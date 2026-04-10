using UnityEngine;

namespace PSXShaderKit
{
    [ExecuteAlways]
    [DefaultExecutionOrder(-100)]
    public class PSXPostProcessEffect : MonoBehaviour
    {
        private const string PREFS_KEY = "PSX_PostProcessing";

        public static PSXPostProcessEffect Instance { get; private set; }

        [Header("Master Toggle")]
        [SerializeField]
        [Tooltip("Enables per-object dithering on all PSX materials.")]
        private bool _EnablePostProcessing = true;

        void Awake()
        {
            Instance = this;

            if (PlayerPrefs.HasKey(PREFS_KEY))
                _EnablePostProcessing = PlayerPrefs.GetInt(PREFS_KEY) == 1;

            UpdateValues();
        }

        void LateUpdate()
        {
            UpdateValues();
        }

        void OnValidate() { UpdateValues(); }
        void OnEnable()  { UpdateValues(); }
        void OnDisable() { Shader.SetGlobalFloat("_PSX_ObjectDithering", 0); }

        void UpdateValues()
        {
            Shader.SetGlobalFloat("_PSX_ObjectDithering", _EnablePostProcessing ? 1 : 0);
        }

        public void SetPostProcessingEnabled(bool value)
        {
            _EnablePostProcessing = value;
            PlayerPrefs.SetInt(PREFS_KEY, value ? 1 : 0);
            PlayerPrefs.Save();
            UpdateValues();
        }

        public bool IsPostProcessingEnabled => _EnablePostProcessing;
    }
}
