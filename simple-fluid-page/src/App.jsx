import BulletinBoard from "./BulletinBoard";
import LiquidEther from "./LiquidEther";

export default function App() {
  return (
    <div
      className="app-container"
      style={{
        width: "100%",
        minHeight: "100vh", // tillåter sidan att växa med innehåll
        position: "relative",
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "flex-start",
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
          resolution={0.3}
          iterationsViscous={16}
          iterationsPoisson={16}
          autoDemo={false}
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
          pointerEvents: "none",
          width: "100%",
          maxWidth: "1000px", // ny: begränsar total bredd
          padding: "2rem 1rem",
          boxSizing: "border-box",
          display: "flex",
          justifyContent: "center",
        }}
      >
        {/* Själva formuläret är klickbart */}
        <div style={{ pointerEvents: "auto", width: "100%" }}>
          <BulletinBoard />
        </div>
      </div>
    </div>
  );
}
