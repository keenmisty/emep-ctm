! <SeaSalt_ml.f90 - A component of the EMEP MSC-W Unified Eulerian
!          Chemical transport Model>
!*****************************************************************************! 
!* 
!*  Copyright (C) 2007-2011 met.no
!* 
!*  Contact information:
!*  Norwegian Meteorological Institute
!*  Box 43 Blindern
!*  0313 OSLO
!*  NORWAY
!*  email: emep.mscw@met.no
!*  http://www.emep.int
!*  
!*    This program is free software: you can redistribute it and/or modify
!*    it under the terms of the GNU General Public License as published by
!*    the Free Software Foundation, either version 3 of the License, or
!*    (at your option) any later version.
!* 
!*    This program is distributed in the hope that it will be useful,
!*    but WITHOUT ANY WARRANTY; without even the implied warranty of
!*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!*    GNU General Public License for more details.
!* 
!*    You should have received a copy of the GNU General Public License
!*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
!*****************************************************************************! 
!_____________________________________________________________________________
! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
! MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD  MOD MOD MOD MOD MOD MOD MOD

                          module SeaSalt_ml

! MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD  MOD MOD MOD MOD MOD MOD MOD
! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

!-----------------------------------------------------------------------------
! Calculates production of sea salt based on: 
! Maartinsson et al.(2003) JGR,100,D8      for particles with Ddry<1.25um  
! Monahan et al.(1986) J.Phys.Oceanogr,10  for particles with Ddry=~1.25-5um  
! This appr. corresponds sea salt aerosol at ambient Rh upto 10 um (inclusion 
! of larger particles is also possible). The sea salt aerosols are aggregated
! in fine, coarse and 'giant' size fractions
! Programmed by Svetlana Tsyro
!-----------------------------------------------------------------------------

 use ChemSpecs_tot_ml,     only : SeaSalt_f, SeaSalt_c, SeaSalt_g
 use ChemChemicals_ml,     only : species
 use EmisDef_ml,           only : NSS, QSSFI, QSSCO, QSSGI
 use GridValues_ml,        only : glat, glon
 use Landuse_ml,           only : LandCover, water_cover
 use LocalVariables_ml,    only : Sub, Grid
 use MetFields_ml,         only : u_ref
 use MetFields_ml,         only : z_bnd, z_mid, sst,  &
                                  nwp_sea, u_ref, foundSST, &
                                   foundws10_met,ws_10m
 use MicroMet_ml,          only : Wind_at_h
 use ModelConstants_ml,    only : KMAX_MID, KMAX_BND, &
                                  DEBUG_SEASALT, DEBUG_i,DEBUG_j
 use Par_ml,               only : MAXLIMAX,MAXLJMAX   ! => x, y dimensions
 use PhysicalConstants_ml, only : CHARNOCK, AVOG ,PI
 use TimeDate_ml,          only : current_date

 !-------------------------------------

  implicit none
  private

  public ::  SeaSalt_flux   ! subroutine

  integer, parameter :: SS_MAAR= 7, SS_MONA= 3, &   !Number size ranges for
                                                    !Maartinsson's and Monahan's 
                        NFIN= 7, NCOA= 2, NGIG=1, & !Number fine&coarse&giant bins     
                        SSdens = 2200.0             ! sea salt density [kg/m3]

  real, save, dimension(SS_MAAR) :: dp3, a, b
  real, save, dimension(SS_MAAR+1) :: log_dbin
  real, save, dimension(SS_MONA) :: temp_Monah, radSS, dSS3
  real, save                     :: n_to_mSS
  real, public, dimension(NSS,MAXLIMAX,MAXLJMAX) :: SS_prod !Sea salt flux

  logical, private, save :: my_first_call = .true.

  contains

! <------------------------------------------------------------------------->

   subroutine SeaSalt_flux (i,j, debug_flag)

  !-----------------------------------------------------------------------
  ! Input: Tw        - sea surface temperature - # -
  !        u10       - wind speed at 10m height 
  ! Output: SS_prod - fluxes of fine and coarse sea salt aerosols [molec/cm3/s]
  !-----------------------------------------------------------------------

   implicit none

   integer, intent(in) :: i,j    ! coordinates of column
   logical, intent(in) :: debug_flag

   real, parameter :: Z10 = 10.0  ! 10m height
   integer :: ii, jj, nlu, ilu, lu
   real    :: invdz, n2m, u10, u10_341, Tw, flux_help, total_flux
   real    :: ss_flux(SS_MAAR+SS_MONA), d3(SS_MAAR+SS_MONA) 
!//---------------------------------------------------
 
  if ( my_first_call ) then 

    call init_seasalt
    
    my_first_call = .false.

  end if !  my_first_call
 !....................................

    SS_prod(:,i,j) = 0.0

    if ( .not. Grid%is_NWPsea .or. Grid%snowice ) return ! quick check


!// Loop over the land-use types present in the grid

     nlu = LandCover(i,j)%ncodes
     do ilu= 1, nlu
       lu =  LandCover(i,j)%codes(ilu)

!// only over water
! Obs!  All water is assumed here to be salt water for now 
!      (as fresh water is not distinguished in the input)

       if ( Sub(lu)%is_water ) then

          if(DEBUG_SEASALT .and. debug_flag) then
              write(6,'(a40)') ' Sea-Salt Check '
              write(6,*)
              write(6,'(a30,4f12.4,f8.2)') '** CHAR, ustar_nwp, d, Z0, SST ** ',&
                   CHARNOCK,Grid%ustar,Sub(lu)%d,Sub(lu)%z0, sst(i,j,1)
          end if

         !.. Calculate wind velocity over water at Z10=10m 

          if(foundws10_met)then
              u10=ws_10m(i,j,1) 
          else 
              u10 = Wind_at_h (Grid%u_ref, Grid%z_ref, Z10, Sub(lu)%d,   &
                           Sub(lu)%z0,  Sub(lu)%invL)
          end if

         if (u10 <= 0.0) u10 = 1.0e-5  ! make sure u10!=0 because of LOG(u10)

         u10_341=exp(log(u10) * (3.41))

         if(DEBUG_SEASALT .and. debug_flag) &
             write(6,'(a,L2,4f12.4,es14.4)')'** U*, Uref, U10, Uh, invL ** ',&
               foundws10_met, Sub(lu)%ustar, Grid%u_ref, u10, &
               Wind_at_h (Grid%u_ref, Grid%z_ref, Z10, Sub(lu)%d,   &
                           Sub(lu)%z0,  Sub(lu)%invL), &
               Sub(lu)%invL

         !.. Sea surface temperature is not always available (e.g. pre-2001 at
         ! MET.NO), so we need an alternative. As emissions are most
         ! sensitive to u* and not T, we ignore differences between Tw and T2
         ! for the default case if SST isn't avialable.

          if ( foundSST ) then
            Tw = sst(i,j,1)
          else
            Tw = Grid%t2
          endif

! ====    Calculate sea salt fluxes in size bins  [part/m2/s] ========
         total_flux = 0.0
!... Fluxes of small aerosols for each size bin (M�rtensson etal,2004)
          do ii = 1, SS_MAAR

               flux_help  = a(ii) * Tw + b(ii)
  
               ss_flux(ii) = flux_help * ( log_dbin(ii+1) - log_dbin(ii) )    &
                                   * u10_341 * 3.84e-6 
               d3(ii) = dp3(ii)  ! diameter cubed

               total_flux =  total_flux + ss_flux(ii)

               if(DEBUG_SEASALT .and. debug_flag) write(6,'(a20,i5,es13.4)') &
                  'Flux Maarten ->  ',ii, ss_flux(ii)
          enddo

!... Fluxes of larger aerosols for each size bin (Monahan etal,1986)
          do ii = 1, SS_MONA
             jj = ii + SS_MAAR

               ss_flux(jj) = temp_Monah (ii) * u10_341

               d3(jj) = dSS3(ii)  ! diameter cubed

               total_flux =  total_flux + ss_flux(ii) 

               if(DEBUG_SEASALT .and. debug_flag) &
                   write(6,'(a20,i5,es13.4)') 'Flux Monah ->  ',ii, ss_flux(jj)
          enddo

   if(DEBUG_SEASALT .and. debug_flag) write(6,'(a20,es13.3)') 'Total SS flux ->  ',  total_flux

!.. conversion factor from [part/m2/s] to [molec/cm3/s]

          invdz  = 1.0e-6 / Grid%DeltaZ       ! 1/dZ [1/cm3]
          n2m = n_to_mSS * invdz *AVOG / species(SeaSalt_f)%molwt *1.0e-15

!.. Fine particles emission [molec/cm3/s]
          do ii = 1, NFIN
               SS_prod(QSSFI,i,j) = SS_prod(QSSFI,i,j)   &
                                  + ss_flux(ii) * d3(ii) * n2m   &
                                  * water_cover(i,j) 
            if(DEBUG_SEASALT .and. debug_flag) &
            write(6,'(a20,i5,2es13.4)') 'Flux fine ->  ',ii,d3(ii),SS_prod(QSSFI,i,j)
          enddo

!..Coarse particles emission [molec/cm3/s]
          do ii = NFIN+1, NFIN+NCOA
               SS_prod(QSSCO,i,j) = SS_prod(QSSCO,i,j)   &
                                  + ss_flux(ii) * d3(ii) * n2m   &
                                  * water_cover(i,j)
            if(DEBUG_SEASALT .and. debug_flag) &
            write(6,'(a20,i5,2es13.4)') 'Flux coarse ->  ',ii,d3(ii),SS_prod(QSSCO,i,j)
          enddo

!..'Giant' particles emission [molec/cm3/s]
          do ii = NFIN+NCOA+1, NFIN+NCOA+NGIG
               SS_prod(QSSGI,i,j) = SS_prod(QSSGI,i,j)   &
                                  + ss_flux(ii) * d3(ii) * n2m   &
                                  * water_cover(i,j)
          enddo

!... Crude fix for the effect of lower salinity in the Baltic Sea

          if ( (glat(i,j) > 52.0 .and. glat(i,j) < 67.0)     .and.   &  
               (glon(i,j) > 13.0 .and. glon(i,j) < 30.0) )   then 
          
                 SS_prod(:,i,j) =  0.5 * SS_prod(:,i,j)
          endif
  
          if(DEBUG_SEASALT .and. debug_flag) write(6,'(a35,2es15.4)')  &
             '>> SS production fine/coarse  >>', &
                SS_prod(QSSFI,i,j), SS_prod(QSSCO,i,j)
                          
       endif  ! water
     enddo  ! LU classes

  end subroutine SeaSalt_flux


!<<---------------------------------------------------------------------------<<

  subroutine init_seasalt

  !------------------------------------------------------------
  ! Assignments and calculations of some help-parameters
  !------------------------------------------------------------

  implicit none

  integer :: i
  real    :: a1, a2
  real, dimension(SS_MONA) :: Rrange, rdry

!//===== Polynomial coeficients from Maartinsson et al. (2004)
  real, parameter, dimension(5) ::    &
        C1 = (/-2.576e35,  5.932e28, -2.867e21, -3.003e13, -2.881e6 /),  &
        C2 = (/-2.452e33,  2.404e27, -8.148e20,  1.183e14, -6.743e6 /),  &
        C3 = (/ 1.085e29, -9.841e23,  3.132e18, -4.165e12,  2.181e6 /),  &

        D1 = (/ 7.188e37, -1.616e31,  6.791e23,  1.829e16,  7.609e8 /),  &
        D2 = (/ 7.368e35, -7.310e29,  2.528e23, -3.787e16,  2.279e9 /),  &
        D3 = (/-2.859e31,  2.601e26, -8.297e20,  1.105e15, -5.800e8 /)

!=== mikrometer in powers
  real, parameter :: MKM  = 1.e-6,  MKM2 = 1.e-12 ,  &  
                     MKM3 = 1.e-18, MKM4 = 1.e-24 
 
!//.. Size bins for Maartinsson's parameterisation (dry diameters):
  real, parameter, dimension(SS_MAAR)::    &
      DP   = (/0.035, 0.075, 0.125, 0.195, 0.335, 0.51, 0.85 /) ! diameters Ddry
  real, parameter, dimension(SS_MAAR+1)::    &
      Dbin = (/0.02, 0.05, 0.1, 0.145, 0.25, 0.419, 0.6, 1.25 /) ! bins' borders Dd
    ! D_80%rh(/0.04, 0.10, 0.2, 0.290, 0.50, 0.838, 1.2, 2.5 /) ! bins' borders D80


!// Size bin borders (for dry R) for Monahan parameterisation
  real, parameter, dimension(SS_MONA+1) ::    &
        RLIM  = (/ 0.625, 1.0, 2.0, 3.0 /)  ! for Rdry
!extended        RLIM  = (/ 0.625, 1.0, 2.0, 3.0, 5.0, 7.0 /)  ! for Rdry
  real, parameter :: K1 = 0.7674, K2 = 3.079, K3 = 2.573e-11, K4 = -1.424
  real, parameter :: third = 1.0/3.0
  real :: lim1, lim2
  real, dimension(SS_MAAR) ::  dp2, dp4  
 !---------------------------------------------------- 

    n_to_mSS = PI * SSdens / 6.0  ! number to mass convertion
 
    log_dbin(:) = log10(Dbin(:))

!.. powers of diameter
     dp2(:) = DP(:)  * DP(:)
     dp3(:) = dp2(:) * DP(:)
     dp4(:) = dp3(:) * DP(:)

!//===== For Maartinsson et al.(2004) parameterisation =======

     a(1:3) = C1(1)*dp4(1:3)*MKM4   + C1(2)*dp3(1:3)  *MKM3        &
            + C1(3)*dp2(1:3)*MKM2   + C1(4)*DP(1:3)   *MKM + C1(5)
     a(4:5) = C2(1)*dp4(4:5)*MKM4   + C2(2)*dp3(4:5)  *MKM3        &
            + C2(3)*dp2(4:5)*MKM2   + C2(4)*DP(4:5)   *MKM + C2(5)
     a(6:7) = C3(1)*dp4(6:7)*MKM4   + C3(2)*dp3(6:7)  *MKM3        &
            + C3(3)*dp2(6:7)*MKM2   + C3(4)*DP(6:7)   *MKM + C3(5)

     b(1:3) = D1(1)*dp4(1:3)*MKM4   + D1(2)*dp3(1:3)  *MKM3        &
            + D1(3)*dp2(1:3)*MKM2   + D1(4)*DP(1:3)   *MKM + D1(5)
     b(4:5) = D2(1)*dp4(4:5)*MKM4   + D2(2)*dp3(4:5)  *MKM3        &
            + D2(3)*dp2(4:5)*MKM2   + D2(4)*DP(4:5)   *MKM + D2(5)
     b(6:7) = D3(1)*dp4(6:7)*MKM4   + D3(2)*dp3(6:7)  *MKM3        &
            + D3(3)*dp2(6:7)*MKM2   + D3(4)*DP(6:7)   *MKM + D3(5)

!//====== For  Monahan et al. (1986) parameterisation  =====

     rdry(1) = 0.8    ! Diameter at 80% ca. 3.1
     rdry(2) = 1.5    !                     6.3
     rdry(3) = 2.5    !                     10.6
 !.. can be extended 
!     rdry(4) = 4.0    !                     17
!     rdry(5) = 6.0    !                     26       

!.. Equilibrium wet radius from Gerber(1985) (Gong&Barrie [1997], JGR)

     do i = 1, SS_MONA
        radSS(i) = ( K1*rdry(i)**K2 /(K3 *rdry(i)**K4 -     &
                     log10(0.8))+rdry(i)**3) ** third
        lim1 = ( K1*RLIM(i+1)**K2 /(K3 *RLIM(i+1)**K4 -     &
                 log10(0.8))+RLIM(i+1)**3) ** third
        lim2 = ( K1*RLIM(i)**K2 /(K3 *RLIM(i)**K4 -         &
                 log10(0.8))+RLIM(i)**3) ** third
        Rrange(i) = lim1 - lim2       ! bin size intervals 
     enddo

!.. Help parameter
     do i = 1, SS_MONA
          a1 = ( 0.380 - log10(radSS(i)) ) / 0.650
          a2 = 1.19 * exp(-a1*a1)

          temp_Monah(i) = 1.373 * radSS(i)**(-3) * Rrange(i) *      &
                          ( 1.0 + 0.057 * radSS(i)**1.05 )* 10.0**a2
     enddo

!// D_dry^3 -  for production of dry SS mass
     dSS3(:) =  ( 2.0 * rdry(:) )**3


   end subroutine init_seasalt
!>>--------------------------------------------------------------------------->>

 end module SeaSalt_ml
