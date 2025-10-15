import BulletinBoard from "./BulletinBoard";
import LiquidEther from "./LiquidEther";

export default function App() {
  return (
    <div
      className="app-container"
      style={{
        width: "100%",
        height: "100vh",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Bakgrundseffekt – alltid aktiv */}
      <div
        className="liquid-bg"
        style={{
          position: "fixed",
          inset: 0,
          zIndex: 0,
          pointerEvents: "auto", // låter musen styra effekten
        }}
      >
        <LiquidEther
          colors={["#5227FF", "#FF9FFC", "#B19EEF"]}
          resolution={0.3}        // sänk för bättre prestanda
          iterationsViscous={16}  // halvera iterationer
          iterationsPoisson={16}  // halvera iterationer
          autoDemo={false}        // avstängd: användarens mus styr hela tiden
          autoSpeed={0.5}
          autoIntensity={2.2}
        />
      </div>

      {/* Transparent lager som tillåter musen att nå effekten även under UI */}
      <div
        style={{
          position: "fixed",
          inset: 0,
          zIndex: 1,
          pointerEvents: "none",
        }}
      />

      {/* Overlay – anslagstavlan (interaktiv, men påverkar inte effekten bakom) */}
      <div
        className="content-overlay"
        style={{
          position: "relative",
          zIndex: 5,
          pointerEvents: "none", // låter musen gå igenom overlay
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          height: "100%",
        }}
      >
        {/* Själva formuläret är klickbart */}
        <div style={{ pointerEvents: "auto" }}>
          <BulletinBoard />
        </div>
      </div>
    </div>
  );
}
