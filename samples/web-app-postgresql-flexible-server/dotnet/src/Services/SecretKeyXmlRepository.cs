using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption.ConfigurationModel;
using Microsoft.AspNetCore.DataProtection.Repositories;

namespace VacationPlanner.Services;

/// <summary>
/// A Data Protection key ring derived deterministically from <c>SECRET_KEY</c>, the Kubernetes Secret the Python
/// sample signs its Flask session cookie with. ASP.NET Core protects its antiforgery tokens and TempData (flash)
/// cookies with Data Protection instead of a signing key; deriving the one key of the ring from the same secret
/// lets every replica of the Deployment validate what another replica issued, which the default per-process key
/// ring cannot offer behind a load balancer.
/// </summary>
public sealed class SecretKeyXmlRepository : IXmlRepository
{
    private readonly XElement _key;

    public SecretKeyXmlRepository(string secretKey)
    {
        var keyMaterial = Encoding.UTF8.GetBytes(secretKey);

        // A 512-bit master key (the size Data Protection generates itself) and a stable key id, both from SECRET_KEY.
        var masterKey = HKDF.DeriveKey(HashAlgorithmName.SHA256, keyMaterial, 64, info: "VacationPlanner.DataProtection.MasterKey"u8.ToArray());
        var keyId = new Guid(HKDF.DeriveKey(HashAlgorithmName.SHA256, keyMaterial, 16, info: "VacationPlanner.DataProtection.KeyId"u8.ToArray()));

        // AES-256-CBC + HMACSHA256, the default algorithms, serialized the way the key manager itself serializes a new key.
        var descriptor = new AuthenticatedEncryptorDescriptor(new AuthenticatedEncryptorConfiguration(), new Secret(masterKey));
        var serialized = descriptor.ExportToXml();

        _key = new XElement("key",
            new XAttribute("id", keyId),
            new XAttribute("version", 1),
            new XElement("creationDate", new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero)),
            new XElement("activationDate", new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero)),
            new XElement("expirationDate", new DateTimeOffset(2999, 12, 31, 0, 0, 0, TimeSpan.Zero)),
            new XElement("descriptor",
                new XAttribute("deserializerType", serialized.DeserializerType.AssemblyQualifiedName!),
                serialized.SerializedDescriptorElement));
    }

    public IReadOnlyCollection<XElement> GetAllElements() => [new XElement(_key)];

    /// <summary>Never called: automatic key generation is disabled, so the key manager has nothing to persist.</summary>
    public void StoreElement(XElement element, string friendlyName) =>
        throw new NotSupportedException("The key ring is derived from SECRET_KEY and cannot be modified.");
}
