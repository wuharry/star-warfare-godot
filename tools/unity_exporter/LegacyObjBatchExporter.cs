using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

// This file is copied into an isolated, throw-away Unity 6 project by
// Prepare-IsolatedProject.ps1. It must not be placed in the legacy Assets tree.
public static class LegacyObjBatchExporter
{
    private const string LegacyRoot = "Assets/Legacy/";

    [Serializable]
    private sealed class BatchReport
    {
        public string unityVersion;
        public string generatedUtc;
        public string coordinateConversion;
        public List<ModelReport> models = new List<ModelReport>();
        public List<string> warnings = new List<string>();
    }

    [Serializable]
    private sealed class ModelReport
    {
        public string name;
        public string source;
        public string obj;
        public int renderers;
        public int vertices;
        public int triangles;
        public int materials;
    }

    [MenuItem("Tools/Legacy Star Warfare/Export Godot OBJs")]
    public static void ExportAll()
    {
        string output = GetArgument("-exportOutput");
        if (string.IsNullOrWhiteSpace(output))
            throw new ArgumentException("Missing required command-line argument: -exportOutput <directory>");

        output = Path.GetFullPath(output);
        Directory.CreateDirectory(output);
        Directory.CreateDirectory(Path.Combine(output, "textures"));

        var report = new BatchReport
        {
            unityVersion = Application.unityVersion,
            generatedUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
            coordinateConversion = "Unity (x,y,z) -> Godot/OBJ (x,y,-z); world transforms and current skinned pose are baked."
        };

        Debug.Log("[LegacyObjBatchExporter] Export output: " + output);
        try
        {
            report.models.Add(ExportLevel1(output, report.warnings));
            report.models.Add(ExportSinglePrefab(
                output, "bug01", LegacyRoot + "Resources/enemy/bug01.prefab", report.warnings, true));
            report.models.Add(ExportSinglePrefab(
                output, "gun00", LegacyRoot + "Resources/weapon/gun00.prefab", report.warnings, true));
            foreach (int weaponId in new[] { 22, 23, 36, 37 })
            {
                string weaponName = "gun" + weaponId.ToString("00", CultureInfo.InvariantCulture);
                report.models.Add(ExportSinglePrefab(
                    output,
                    weaponName,
                    LegacyRoot + "Resources/weapon/" + weaponName + ".prefab",
                    report.warnings,
                    true));
            }

            TryOptional(() => ExportSinglePrefab(
                    output, "player", LegacyRoot + "Resources/avatar/Player.prefab", report.warnings, false),
                report, output, "player");

            TryOptional(() => ExportArmor01(output, report.warnings), report, output, "armor01");

            string reportPath = Path.Combine(output, "export_report.json");
            File.WriteAllText(reportPath, JsonUtility.ToJson(report, true), new UTF8Encoding(false));
            AssetDatabase.Refresh();
            Debug.Log("[LegacyObjBatchExporter] Finished " + report.models.Count + " models. Report: " + reportPath);
        }
        catch (Exception exception)
        {
            Debug.LogException(exception);
            EditorApplication.Exit(1);
            throw;
        }
    }

    private static void TryOptional(Func<ModelReport> operation, BatchReport batch, string output, string modelName)
    {
        try
        {
            ModelReport model = operation();
            if (model.vertices == 0 || model.triangles == 0)
                throw new InvalidOperationException(modelName + " produced no usable geometry.");
            batch.models.Add(model);
        }
        catch (Exception exception)
        {
            string message = "Optional model '" + modelName + "' was not exported: " + exception.Message;
            batch.warnings.Add(message);
            Debug.LogWarning("[LegacyObjBatchExporter] " + message);
            DeleteIfPresent(Path.Combine(output, modelName + ".obj"));
            DeleteIfPresent(Path.Combine(output, modelName + ".mtl"));
        }
    }

    private static ModelReport ExportLevel1(string output, List<string> warnings)
    {
        const string scenePath = LegacyRoot + "Scenes/Level1.unity";
        RequireAsset(scenePath);
        Scene scene = EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);

        var allRenderers = scene.GetRootGameObjects()
            .SelectMany(root => root.GetComponentsInChildren<MeshRenderer>(true))
            .Where(IsVisibleRenderer)
            .Where(renderer => renderer.GetComponent<MeshFilter>() != null)
            .Where(renderer => renderer.GetComponent<MeshFilter>().sharedMesh != null)
            .ToList();

        var staticRenderers = allRenderers
            .Where(renderer => GameObjectUtility.GetStaticEditorFlags(renderer.gameObject) != 0)
            .Cast<Renderer>()
            .ToList();

        if (staticRenderers.Count == 0)
        {
            warnings.Add("Level1 had no objects carrying Unity static flags; all visible MeshRenderers were exported.");
            staticRenderers = allRenderers.Cast<Renderer>().ToList();
        }

        ModelReport result = ExportRenderers(
            output,
            "level1_static",
            scenePath + " (static MeshRenderers)",
            staticRenderers,
            warnings,
            false);
        RequireGeometry(result);
        return result;
    }

    private static ModelReport ExportSinglePrefab(
        string output,
        string modelName,
        string prefabPath,
        List<string> warnings,
        bool required)
    {
        RequireAsset(prefabPath);
        GameObject root = null;
        try
        {
            root = PrefabUtility.LoadPrefabContents(prefabPath);
            Renderer[] renderers = root.GetComponentsInChildren<Renderer>(true)
                .Where(IsExportablePrefabRenderer)
                .ToArray();
            ModelReport result = ExportRenderers(output, modelName, prefabPath, renderers, warnings, true);
            if (required)
                RequireGeometry(result);
            return result;
        }
        finally
        {
            if (root != null)
                PrefabUtility.UnloadPrefabContents(root);
        }
    }

    private static ModelReport ExportArmor01(string output, List<string> warnings)
    {
        string[] parts = { "Body", "Hand", "Foot", "Head", "Bag" };
        string objPath = Path.Combine(output, "armor01.obj");
        string mtlPath = Path.Combine(output, "armor01.mtl");
        var report = new ModelReport
        {
            name = "armor01",
            source = LegacyRoot + "Resources/avatar/01/{Body,Hand,Foot,Head,Bag}.prefab",
            obj = "armor01.obj"
        };

        using (var writer = new ObjModelWriter(objPath, mtlPath, output, warnings))
        {
            foreach (string part in parts)
            {
                string prefabPath = LegacyRoot + "Resources/avatar/01/" + part + ".prefab";
                GameObject root = null;
                try
                {
                    RequireAsset(prefabPath);
                    root = PrefabUtility.LoadPrefabContents(prefabPath);
                    foreach (Renderer renderer in root.GetComponentsInChildren<Renderer>(true).Where(IsExportablePrefabRenderer))
                        writer.Append(renderer, "armor01/" + part);
                }
                catch (Exception exception)
                {
                    string message = "armor01 part '" + part + "' was skipped: " + exception.Message;
                    warnings.Add(message);
                    Debug.LogWarning("[LegacyObjBatchExporter] " + message);
                }
                finally
                {
                    if (root != null)
                        PrefabUtility.UnloadPrefabContents(root);
                }
            }
            writer.FillReport(report);
        }
        return report;
    }

    private static ModelReport ExportRenderers(
        string output,
        string modelName,
        string source,
        IEnumerable<Renderer> renderers,
        List<string> warnings,
        bool skipVisualHelpers)
    {
        string objPath = Path.Combine(output, modelName + ".obj");
        string mtlPath = Path.Combine(output, modelName + ".mtl");
        var result = new ModelReport { name = modelName, source = source, obj = modelName + ".obj" };

        using (var writer = new ObjModelWriter(objPath, mtlPath, output, warnings))
        {
            foreach (Renderer renderer in renderers)
            {
                if (skipVisualHelpers && IsVisualHelper(renderer.gameObject.name))
                    continue;
                writer.Append(renderer, modelName);
            }
            writer.FillReport(result);
        }
        return result;
    }

    private static bool IsVisibleRenderer(MeshRenderer renderer)
    {
        return renderer != null && renderer.enabled && !renderer.forceRenderingOff && renderer.gameObject.activeInHierarchy;
    }

    private static bool IsExportablePrefabRenderer(Renderer renderer)
    {
        if (renderer == null || !renderer.enabled || renderer.forceRenderingOff || !renderer.gameObject.activeInHierarchy)
            return false;
        if (renderer is SkinnedMeshRenderer skinned)
            return skinned.sharedMesh != null;
        if (renderer is MeshRenderer)
        {
            MeshFilter filter = renderer.GetComponent<MeshFilter>();
            return filter != null && filter.sharedMesh != null;
        }
        return false;
    }

    private static bool IsVisualHelper(string objectName)
    {
        string value = (objectName ?? string.Empty).Trim().ToLowerInvariant();
        return value == "shadow" || value.StartsWith("shadow(") || value.Contains("gunfire");
    }

    private static void RequireAsset(string assetPath)
    {
        if (AssetDatabase.LoadMainAssetAtPath(assetPath) == null)
            throw new FileNotFoundException("Unity could not import required asset '" + assetPath + "'.");
    }

    private static void RequireGeometry(ModelReport report)
    {
        if (report.vertices == 0 || report.triangles == 0)
            throw new InvalidOperationException("Required model '" + report.name + "' produced no usable geometry.");
    }

    private static string GetArgument(string name)
    {
        string[] args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; ++i)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }
        return null;
    }

    private static void DeleteIfPresent(string path)
    {
        if (File.Exists(path))
            File.Delete(path);
    }

    private sealed class ObjModelWriter : IDisposable
    {
        private readonly StreamWriter obj;
        private readonly StreamWriter mtl;
        private readonly string outputDirectory;
        private readonly List<string> warnings;
        private readonly Dictionary<string, string> materialNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> textureNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private int vertexOffset = 1;
        private int uvOffset = 1;
        private int normalOffset = 1;
        private int rendererCount;
        private int vertexCount;
        private int triangleCount;
        private bool disposed;

        public ObjModelWriter(string objPath, string mtlPath, string outputDirectory, List<string> warnings)
        {
            this.outputDirectory = outputDirectory;
            this.warnings = warnings;
            obj = NewWriter(objPath);
            mtl = NewWriter(mtlPath);
            obj.WriteLine("# Star Warfare legacy Unity export for Godot");
            obj.WriteLine("# Coordinates converted from Unity by reflecting the Z axis");
            obj.WriteLine("mtllib " + Path.GetFileName(mtlPath));
            mtl.WriteLine("# Star Warfare legacy Unity material export");
        }

        public void Append(Renderer renderer, string groupPrefix)
        {
            Mesh mesh = null;
            bool destroyMesh = false;
            try
            {
                if (renderer is SkinnedMeshRenderer skinned)
                {
                    mesh = new Mesh { name = skinned.sharedMesh != null ? skinned.sharedMesh.name + "_baked" : "baked" };
                    skinned.BakeMesh(mesh, true);
                    destroyMesh = true;
                }
                else
                {
                    MeshFilter filter = renderer.GetComponent<MeshFilter>();
                    mesh = filter != null ? filter.sharedMesh : null;
                }

                if (mesh == null || mesh.vertexCount == 0)
                    return;
                if (!mesh.isReadable)
                {
                    Warn("Mesh '" + mesh.name + "' on '" + HierarchyPath(renderer.transform) + "' is not readable and was skipped.");
                    return;
                }

                AppendMesh(mesh, renderer, groupPrefix);
            }
            catch (Exception exception)
            {
                Warn("Renderer '" + HierarchyPath(renderer.transform) + "' was skipped: " + exception.Message);
            }
            finally
            {
                if (destroyMesh && mesh != null)
                    UnityEngine.Object.DestroyImmediate(mesh);
            }
        }

        public void FillReport(ModelReport report)
        {
            report.renderers = rendererCount;
            report.vertices = vertexCount;
            report.triangles = triangleCount;
            report.materials = materialNames.Count;
        }

        private void AppendMesh(Mesh mesh, Renderer renderer, string groupPrefix)
        {
            Vector3[] vertices = mesh.vertices;
            Vector3[] normals = mesh.normals;
            Vector2[] uvs = mesh.uv;
            bool hasNormals = normals != null && normals.Length == vertices.Length;
            bool hasUvs = uvs != null && uvs.Length == vertices.Length;
            Matrix4x4 world = renderer.localToWorldMatrix;
            Matrix4x4 normalMatrix = world.inverse.transpose;

            string hierarchy = HierarchyPath(renderer.transform);
            string groupName = Sanitize(groupPrefix + "_" + hierarchy);
            obj.WriteLine();
            obj.WriteLine("o " + groupName);
            obj.WriteLine("g " + groupName);

            foreach (Vector3 vertex in vertices)
            {
                Vector3 converted = world.MultiplyPoint3x4(vertex);
                converted.z = -converted.z;
                obj.WriteLine("v " + F(converted.x) + " " + F(converted.y) + " " + F(converted.z));
            }
            if (hasUvs)
            {
                foreach (Vector2 uv in uvs)
                    obj.WriteLine("vt " + F(uv.x) + " " + F(uv.y));
            }
            if (hasNormals)
            {
                foreach (Vector3 normal in normals)
                {
                    Vector3 converted = normalMatrix.MultiplyVector(normal).normalized;
                    converted.z = -converted.z;
                    obj.WriteLine("vn " + F(converted.x) + " " + F(converted.y) + " " + F(converted.z));
                }
            }

            Material[] materials = renderer.sharedMaterials ?? Array.Empty<Material>();
            int subMeshCount = mesh.subMeshCount;
            for (int subMesh = 0; subMesh < subMeshCount; ++subMesh)
            {
                if (mesh.GetTopology(subMesh) != MeshTopology.Triangles)
                {
                    Warn("Non-triangle submesh " + subMesh + " on '" + hierarchy + "' was skipped.");
                    continue;
                }

                Material material = subMesh < materials.Length ? materials[subMesh] : null;
                string materialName = GetOrWriteMaterial(material);
                obj.WriteLine("usemtl " + materialName);
                int[] indices = mesh.GetIndices(subMesh);
                bool reverseWinding = world.determinant >= 0f;
                for (int i = 0; i + 2 < indices.Length; i += 3)
                {
                    int a = indices[i];
                    int b = indices[i + 1];
                    int c = indices[i + 2];
                    if (reverseWinding)
                    {
                        int swap = b;
                        b = c;
                        c = swap;
                    }
                    obj.WriteLine("f " + Face(a, hasUvs, hasNormals) + " " + Face(b, hasUvs, hasNormals) + " " + Face(c, hasUvs, hasNormals));
                    triangleCount++;
                }
            }

            rendererCount++;
            vertexCount += vertices.Length;
            vertexOffset += vertices.Length;
            if (hasUvs)
                uvOffset += uvs.Length;
            if (hasNormals)
                normalOffset += normals.Length;
        }

        private string Face(int zeroBasedIndex, bool hasUvs, bool hasNormals)
        {
            int v = vertexOffset + zeroBasedIndex;
            if (hasUvs && hasNormals)
                return v + "/" + (uvOffset + zeroBasedIndex) + "/" + (normalOffset + zeroBasedIndex);
            if (hasUvs)
                return v + "/" + (uvOffset + zeroBasedIndex);
            if (hasNormals)
                return v + "//" + (normalOffset + zeroBasedIndex);
            return v.ToString(CultureInfo.InvariantCulture);
        }

        private string GetOrWriteMaterial(Material material)
        {
            string assetPath = material != null ? AssetDatabase.GetAssetPath(material) : string.Empty;
            string key = material == null ? "<null>" : assetPath + "#" + material.GetInstanceID();
            if (materialNames.TryGetValue(key, out string existing))
                return existing;

            string baseName = material != null ? material.name : "missing_material";
            string materialName = Sanitize(baseName) + "_" + (materialNames.Count + 1).ToString(CultureInfo.InvariantCulture);
            materialNames[key] = materialName;

            Color color = ReadMaterialColor(material);
            mtl.WriteLine();
            mtl.WriteLine("newmtl " + materialName);
            mtl.WriteLine("Ka 0 0 0");
            mtl.WriteLine("Kd " + F(color.r) + " " + F(color.g) + " " + F(color.b));
            mtl.WriteLine("Ks 0.04 0.04 0.04");
            mtl.WriteLine("Ns 32");
            mtl.WriteLine("d " + F(color.a));
            mtl.WriteLine("illum 2");

            Texture texture = ReadMainTexture(material);
            string textureRelative = CopyTexture(texture);
            if (!string.IsNullOrEmpty(textureRelative))
                mtl.WriteLine("map_Kd " + textureRelative.Replace('\\', '/'));
            return materialName;
        }

        private string CopyTexture(Texture texture)
        {
            if (texture == null)
                return null;
            string assetPath = AssetDatabase.GetAssetPath(texture);
            string key = string.IsNullOrEmpty(assetPath) ? "instance:" + texture.GetInstanceID() : assetPath;
            if (textureNames.TryGetValue(key, out string prior))
                return prior;

            string sourcePath = string.IsNullOrEmpty(assetPath)
                ? null
                : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? string.Empty, assetPath));
            string extension = sourcePath == null ? string.Empty : Path.GetExtension(sourcePath).ToLowerInvariant();
            string[] directlyUsable = { ".png", ".jpg", ".jpeg", ".tga", ".bmp", ".dds", ".webp", ".exr", ".hdr" };
            string guid = string.IsNullOrEmpty(assetPath) ? string.Empty : AssetDatabase.AssetPathToGUID(assetPath);
            string prefix = string.IsNullOrEmpty(guid) ? Math.Abs(texture.GetInstanceID()).ToString("x8") : guid.Substring(0, Math.Min(8, guid.Length));
            string safeBaseName = Sanitize(Path.GetFileNameWithoutExtension(string.IsNullOrEmpty(assetPath) ? texture.name : assetPath));
            string outputExtension = directlyUsable.Contains(extension) ? extension : ".png";
            string fileName = prefix + "_" + safeBaseName + outputExtension;
            string relativePath = "textures/" + fileName;
            string destination = Path.Combine(outputDirectory, "textures", fileName);

            try
            {
                if (sourcePath != null && File.Exists(sourcePath) && directlyUsable.Contains(extension))
                {
                    File.Copy(sourcePath, destination, true);
                }
                else
                {
                    Texture2D texture2D = MakeTextureReadable(texture, assetPath);
                    if (texture2D == null)
                        throw new InvalidOperationException("Texture is not a readable Texture2D.");
                    File.WriteAllBytes(destination, texture2D.EncodeToPNG());
                }
                textureNames[key] = relativePath;
                return relativePath;
            }
            catch (Exception exception)
            {
                Warn("Texture '" + texture.name + "' could not be copied: " + exception.Message);
                return null;
            }
        }

        private static Texture2D MakeTextureReadable(Texture texture, string assetPath)
        {
            Texture2D texture2D = texture as Texture2D;
            if (texture2D == null)
                return null;
            try
            {
                texture2D.GetPixel(0, 0);
                return texture2D;
            }
            catch (UnityException)
            {
                var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
                if (importer == null)
                    return null;
                importer.isReadable = true;
                importer.SaveAndReimport();
                return AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
            }
        }

        private static Texture ReadMainTexture(Material material)
        {
            if (material == null)
                return null;
            string[] preferred = { "_MainTex", "_BaseMap", "_BaseColorMap" };
            foreach (string property in preferred)
            {
                try
                {
                    if (material.HasProperty(property))
                    {
                        Texture value = material.GetTexture(property);
                        if (value != null)
                            return value;
                    }
                }
                catch { }
            }

            try
            {
                var serialized = new SerializedObject(material);
                SerializedProperty environments = serialized.FindProperty("m_SavedProperties.m_TexEnvs");
                if (environments != null && environments.isArray)
                {
                    Texture fallback = null;
                    for (int i = 0; i < environments.arraySize; ++i)
                    {
                        SerializedProperty pair = environments.GetArrayElementAtIndex(i);
                        SerializedProperty first = pair.FindPropertyRelative("first");
                        SerializedProperty second = pair.FindPropertyRelative("second");
                        SerializedProperty value = second != null ? second.FindPropertyRelative("m_Texture") : null;
                        Texture found = value != null ? value.objectReferenceValue as Texture : null;
                        if (found == null)
                            continue;
                        if (fallback == null)
                            fallback = found;
                        if (first != null && preferred.Contains(first.stringValue))
                            return found;
                    }
                    return fallback;
                }
            }
            catch { }
            return null;
        }

        private static Color ReadMaterialColor(Material material)
        {
            if (material == null)
                return Color.white;
            string[] preferred = { "_Color", "_BaseColor" };
            foreach (string property in preferred)
            {
                try
                {
                    if (material.HasProperty(property))
                        return material.GetColor(property);
                }
                catch { }
            }

            try
            {
                var serialized = new SerializedObject(material);
                SerializedProperty colors = serialized.FindProperty("m_SavedProperties.m_Colors");
                if (colors != null && colors.isArray)
                {
                    for (int i = 0; i < colors.arraySize; ++i)
                    {
                        SerializedProperty pair = colors.GetArrayElementAtIndex(i);
                        SerializedProperty first = pair.FindPropertyRelative("first");
                        SerializedProperty second = pair.FindPropertyRelative("second");
                        if (first != null && second != null && preferred.Contains(first.stringValue))
                            return second.colorValue;
                    }
                }
            }
            catch { }
            return Color.white;
        }

        private void Warn(string message)
        {
            warnings.Add(message);
            Debug.LogWarning("[LegacyObjBatchExporter] " + message);
        }

        public void Dispose()
        {
            if (disposed)
                return;
            disposed = true;
            obj.Dispose();
            mtl.Dispose();
        }

        private static StreamWriter NewWriter(string path)
        {
            return new StreamWriter(path, false, new UTF8Encoding(false), 1024 * 1024);
        }
    }

    private static string HierarchyPath(Transform transform)
    {
        var names = new Stack<string>();
        Transform current = transform;
        while (current != null)
        {
            names.Push(current.name);
            current = current.parent;
        }
        return string.Join("/", names.ToArray());
    }

    private static string Sanitize(string value)
    {
        string result = Regex.Replace(value ?? "unnamed", "[^A-Za-z0-9_.-]+", "_").Trim('_');
        return string.IsNullOrEmpty(result) ? "unnamed" : result;
    }

    private static string F(float value)
    {
        if (Mathf.Abs(value) < 0.00000001f)
            value = 0f;
        return value.ToString("R", CultureInfo.InvariantCulture);
    }
}
