import LiquidEther from './LiquidEther';

export default function App() {
  return (
    <div style={{ width: '100%', height: '100vh' }}>
      <LiquidEther
        colors={["#5227FF", "#FF9FFC", "#B19EEF"]}
        resolution={0.3}        // sänk för bättre prestanda
        iterationsViscous={16}  // halvera iterationer
        iterationsPoisson={16}  // halvera iterationer
        autoDemo={true}
        autoSpeed={0.5}
        autoIntensity={2.2}
      />
    </div>
  );
}
