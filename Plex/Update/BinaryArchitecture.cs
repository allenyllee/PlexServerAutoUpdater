using System;
using System.IO;

namespace TE.Plex.Update
{
    public static class BinaryArchitecture
    {
        public static bool Is64Bit(string path)
        {
            using (var reader = new BinaryReader(File.OpenRead(path)))
            {
                if (reader.BaseStream.Length < 64 || reader.ReadUInt16() != 0x5a4d)
                    throw new InvalidDataException("Invalid Plex executable DOS header.");
                reader.BaseStream.Position = 0x3c;
                int offset = reader.ReadInt32();
                if (offset < 64 || offset > reader.BaseStream.Length - 24)
                    throw new InvalidDataException("Invalid Plex executable PE offset.");
                reader.BaseStream.Position = offset;
                if (reader.ReadUInt32() != 0x00004550)
                    throw new InvalidDataException("Invalid Plex executable PE signature.");
                ushort machine = reader.ReadUInt16();
                if (machine == 0x8664) return true;
                if (machine == 0x014c) return false;
                throw new InvalidDataException("Unsupported Plex executable architecture.");
            }
        }
    }
}
