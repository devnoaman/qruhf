package dev.qruhf.qruhf;
import org.junit.Test;
import static org.junit.Assert.assertEquals;
public class QruhfPluginTest {
  @Test public void epcHexPreservesLeadingZeroAndUnsignedBytes() {
    assertEquals("0080FF0A", QruhfPlugin.hex(new byte[]{0, (byte)128, (byte)255, 10}));
  }
}
