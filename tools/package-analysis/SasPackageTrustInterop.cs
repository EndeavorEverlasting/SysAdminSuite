using System;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

namespace Sas.PackageTrust
{
    public sealed class OptionalDate
    {
        public bool HasValue { get; set; }
        public DateTime Value { get; set; }
    }

    public sealed class VerificationResult
    {
        public int ResultCode { get; set; }
        public string SignerSubject { get; set; }
        public string SignerThumbprint { get; set; }
        public OptionalDate SignerNotBefore { get; set; } = new OptionalDate();
        public OptionalDate SignerNotAfter { get; set; } = new OptionalDate();
        public bool CacheOnlyUrlRetrieval { get; set; }
        public bool OnlineRevocationChecked { get; set; }
    }

    public static class WinTrustVerifier
    {
        private const uint WTD_UI_NONE = 2;
        private const uint WTD_REVOKE_NONE = 0;
        private const uint WTD_CHOICE_FILE = 1;
        private const uint WTD_STATEACTION_VERIFY = 1;
        private const uint WTD_STATEACTION_CLOSE = 2;
        private const uint WTD_REVOCATION_CHECK_NONE = 0x10;
        private const uint WTD_CACHE_ONLY_URL_RETRIEVAL = 0x1000;
        private const uint WTD_DISABLE_MD2_MD4 = 0x2000;

        private static readonly Guid GenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WINTRUST_FILE_INFO
        {
            public uint cbStruct;
            [MarshalAs(UnmanagedType.LPWStr)] public string pcwszFilePath;
            public IntPtr hFile;
            public IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WINTRUST_DATA
        {
            public uint cbStruct;
            public IntPtr pPolicyCallbackData;
            public IntPtr pSIPClientData;
            public uint dwUIChoice;
            public uint fdwRevocationChecks;
            public uint dwUnionChoice;
            public IntPtr pFile;
            public uint dwStateAction;
            public IntPtr hWVTStateData;
            public IntPtr pwszURLReference;
            public uint dwProvFlags;
            public uint dwUIContext;
            public IntPtr pSignatureSettings;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CRYPT_PROVIDER_CERT
        {
            public uint cbStruct;
            public IntPtr pCert;
            [MarshalAs(UnmanagedType.Bool)] public bool fCommercial;
            [MarshalAs(UnmanagedType.Bool)] public bool fTrustedRoot;
            [MarshalAs(UnmanagedType.Bool)] public bool fSelfSigned;
            [MarshalAs(UnmanagedType.Bool)] public bool fTestCert;
            public uint dwRevokedReason;
            public uint dwConfidence;
            public uint dwError;
            public IntPtr pTrustListContext;
            [MarshalAs(UnmanagedType.Bool)] public bool fTrustListSignerCert;
            public IntPtr pCtlContext;
            public uint dwCtlError;
            [MarshalAs(UnmanagedType.Bool)] public bool fIsCyclic;
            public IntPtr pChainElement;
        }

        [DllImport("wintrust.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int WinVerifyTrust(IntPtr hwnd, [In] ref Guid pgActionID, IntPtr pWVTData);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern IntPtr WTHelperProvDataFromStateData(IntPtr hStateData);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr pProvData, uint idxSigner, [MarshalAs(UnmanagedType.Bool)] bool fCounterSigner, uint idxCounterSigner);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        private static extern IntPtr WTHelperGetProvCertFromChain(IntPtr pSgnr, uint idxCert);

        public static VerificationResult Verify(string path)
        {
            WINTRUST_FILE_INFO fileInfo = new WINTRUST_FILE_INFO();
            fileInfo.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
            fileInfo.pcwszFilePath = path;
            fileInfo.hFile = IntPtr.Zero;
            fileInfo.pgKnownSubject = IntPtr.Zero;

            IntPtr fileInfoPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
            IntPtr dataPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_DATA)));
            VerificationResult output = new VerificationResult();
            output.CacheOnlyUrlRetrieval = true;
            output.OnlineRevocationChecked = false;

            try
            {
                Marshal.StructureToPtr(fileInfo, fileInfoPtr, false);
                WINTRUST_DATA data = new WINTRUST_DATA();
                data.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
                data.pPolicyCallbackData = IntPtr.Zero;
                data.pSIPClientData = IntPtr.Zero;
                data.dwUIChoice = WTD_UI_NONE;
                data.fdwRevocationChecks = WTD_REVOKE_NONE;
                data.dwUnionChoice = WTD_CHOICE_FILE;
                data.pFile = fileInfoPtr;
                data.dwStateAction = WTD_STATEACTION_VERIFY;
                data.hWVTStateData = IntPtr.Zero;
                data.pwszURLReference = IntPtr.Zero;
                data.dwProvFlags = WTD_REVOCATION_CHECK_NONE | WTD_CACHE_ONLY_URL_RETRIEVAL | WTD_DISABLE_MD2_MD4;
                data.dwUIContext = 1;
                data.pSignatureSettings = IntPtr.Zero;
                Marshal.StructureToPtr(data, dataPtr, false);

                Guid action = GenericVerifyV2;
                output.ResultCode = WinVerifyTrust(new IntPtr(-1), ref action, dataPtr);
                data = (WINTRUST_DATA)Marshal.PtrToStructure(dataPtr, typeof(WINTRUST_DATA));
                if (data.hWVTStateData != IntPtr.Zero)
                {
                    IntPtr providerData = WTHelperProvDataFromStateData(data.hWVTStateData);
                    if (providerData != IntPtr.Zero)
                    {
                        IntPtr signer = WTHelperGetProvSignerFromChain(providerData, 0, false, 0);
                        if (signer != IntPtr.Zero)
                        {
                            IntPtr providerCertPtr = WTHelperGetProvCertFromChain(signer, 0);
                            if (providerCertPtr != IntPtr.Zero)
                            {
                                CRYPT_PROVIDER_CERT providerCert = (CRYPT_PROVIDER_CERT)Marshal.PtrToStructure(providerCertPtr, typeof(CRYPT_PROVIDER_CERT));
                                if (providerCert.pCert != IntPtr.Zero)
                                {
                                    using (X509Certificate2 cert = new X509Certificate2(providerCert.pCert))
                                    {
                                        output.SignerSubject = cert.Subject;
                                        output.SignerThumbprint = cert.Thumbprint;
                                        output.SignerNotBefore.HasValue = true;
                                        output.SignerNotBefore.Value = cert.NotBefore.ToUniversalTime();
                                        output.SignerNotAfter.HasValue = true;
                                        output.SignerNotAfter.Value = cert.NotAfter.ToUniversalTime();
                                    }
                                }
                            }
                        }
                    }

                    data.dwStateAction = WTD_STATEACTION_CLOSE;
                    Marshal.StructureToPtr(data, dataPtr, true);
                    WinVerifyTrust(new IntPtr(-1), ref action, dataPtr);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(dataPtr);
                Marshal.DestroyStructure(fileInfoPtr, typeof(WINTRUST_FILE_INFO));
                Marshal.FreeHGlobal(fileInfoPtr);
            }
            return output;
        }
    }
}
