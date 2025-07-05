import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

const VaultModule = buildModule('Vault', (m) => {
  const deployer = m.getAccount(0);
  const tokenAddress = process.env.TOKEN_ADDRES;
  if (!tokenAddress) {
    throw new Error("TOKEN_ADDRESS environment variable must be set");
  }
  const externalVault0 = m.contract('ExternalVault');
  const externalVault1 = m.contract('ExternalVault');
  const externalVault2 = m.contract('ExternalVault');
  const externalVaults = [externalVault0, externalVault1, externalVault2];
  
  const Vault = m.contract('Vault', [deployer, tokenAddress, externalVaults]);

  const riddles = [
    // [
    //   'riddle0',
    //   'Endless Runner',
    //   'It never stops yet never moves an inch.',
    //   'I’m always running but never move, I have no legs yet pass you by. You can’t hold me, though you try. What am I?',
    //   '0x26ecf9f34dfcfc713e50762298662c2ec5dfe3f039a01c9074476b956e53ecdd',
    // ], // time
    // [
    //   'riddle1',
    //   'Pungent Protector',
    //   'A kitchen staple that keeps more than vampires at bay.',
    //   'I’m a bulb that’s not for light, with cloves that ward off bites at night. In the kitchen, I add zest, but my smell might fail a breath test. What am I?',
    //   '0x258d432e564772417c74674fc0cb7048f01bccdd2c06cb6bc7c9d778b04c1ab4',
    // ], // garlic
    // [
    //   'riddle2',
    //   'Invisible Echo',
    //   'Voiceless and bodiless, yet it answers back.',
    //   'I speak without a mouth and hear without ears. I have no body, but I come alive with the wind. What am I?',
    //   '0x21053b27f95ddcb9eb7a133972ab9607583517ed02cbb9883cda95c549de38bb',
    // ], // echo
    // [
    //   'riddle3',
    //   'Waxing and Waning',
    //   'Young it’s tall, aged it’s short—but still it burns.',
    //   'I’m tall when I’m young, and I’m short when I’m old. What am I?',
    //   '0x278bb843a6daf54f20ce1e095658adfc0562ce7aacea56dc2703c3b12a6bf0fe',
    // ], // candle
    // [
    //   'riddle4',
    //   'Corner Traveler',
    //   'It sails the globe without leaving home.',
    //   'What can travel around the world while staying in a corner?',
    //   '0x1685ce55c39275fff29aeaed45d51ac3e324d7c7595162b45dbe187707a955ab',
    // ], // stamp
  ];

  let prevFuture: any | undefined;

  // for (const [id, q, t, e, h] of riddles) {
  //   m.call(factory, 'createRiddle', [q, t, e, h], {
  //     id,
  //     value: 1_000n,
  //     after: prevFuture,
  //   });
  // }

  return {};
});
export default VaultModule;
