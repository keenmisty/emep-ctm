! <Runchem_ml.f90 - A component of the EMEP MSC-W Unified Eulerian
!          Chemical transport Model>
!*****************************************************************************! 
!* 
!*  Copyright (C) 2011 met.no
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

                          module RunChem_ml

! MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD MOD  MOD MOD MOD MOD MOD MOD MOD
! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
!----------------------------------------------------------------------
! Calls for routines calculating chemical and physical processes: 
! irreversible and equilibrium chemistry, dry and wet deposition,
! sea salt production, particle water etc.
!    
!----------------------------------------------------------------------

   use My_Aerosols_ml,    only: My_MARS, My_EQSAM, AERO_DYNAMICS,      &
                                EQUILIB_EMEP, EQUILIB_MARS, EQUILIB_EQSAM,  &
                                Aero_water   !DUST -> USE_DUST
   use My_Timing_ml,      only: Code_timer, Add_2timing,  &
                                tim_before, tim_after

   use Ammonium_ml,       only: Ammonium
   use AOD_PM_ml,         only: AOD_calc
   use Aqueous_ml,        only: Setup_Clouds, prclouds_present, WetDeposition
   use Biogenics_ml,      only: BIO_ISOP, BIO_TERP, setup_bio !rcbio for debug
   use CellMet_ml,        only: Get_CellMet
   use CheckStop_ml,      only: CheckStop
   use Chemfields_ml,     only: xn_adv    ! For DEBUG 
   use Chemsolver_ml,     only: chemistry
   use DefPhotolysis_ml,  only: setup_phot
   use DryDep_ml,         only: drydep
   use DustProd_ml,       only: WindDust
   use ChemSpecs_tot_ml                   ! DEBUG ONLY
   use ChemSpecs_adv_ml                   ! DEBUG ONLY
   use GridValues_ml,     only : debug_proc, debug_li, debug_lj
   use Io_Progs_ml,       only : datewrite
   use ModelConstants_ml, only : USE_DUST, USE_SEASALT, USE_AOD, & 
                                 PPB, KMAX_MID, dt_advec,        &
                                 nprint, END_OF_EMEPDAY,         &
                                  
                  DebugCell,  DEBUG_AOT, & ! DEBUG only
                  DEBUG => DEBUG_RUNCHEM, DEBUG_i, DEBUG_j,nstep, NPROC
   use OrganicAerosol_ml, only: ORGANIC_AEROSOLS, OrganicAerosol
   use Par_ml,            only : lj0,lj1,li0,li1, limax, ljmax  &
                                ,gi0, gj0, me &    !! for testing
                                ,IRUNBEG, JRUNBEG  !! for testing
   use SeaSalt_ml,        only: SeaSalt_flux
   use Setup_1d_ml,       only: setup_1d, &
                                setup_rcemis, reset_3d
                                !FUTURE setup_nh3  ! NH3emis (NMR-NH3 project)
   use Setup_1dfields_ml, only: first_call, rcbio,  &
                                amk, rcemis, xn_2d  ! DEBUG for testing
   use TimeDate_ml,       only: current_date

!--------------------------------
   implicit none
   private

   public :: runchem

contains

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

subroutine runchem(numt)

   integer, intent(in) :: numt      

!  local
   integer :: i, j
   integer :: errcode
   integer :: nmonth, nday, nhour     
   logical ::  Jan_1st, End_of_Run
   logical :: ambient
   logical ::  debug_flag    ! =>   Set true for selected i,j
   !TEST real, dimension(limax,ljmax) :: aotpre, aotpost

! =============================

   nmonth = current_date%month
   nday   = current_date%day
   nhour  = current_date%hour

   Jan_1st    = ( nmonth == 1 .and. nday == 1 )
   End_of_Run = ( mod(numt,nprint) == 0       )

! Processes calls 

   errcode = 0

    do j = lj0, lj1
      do i = li0, li1

          call Code_Timer(tim_before)

         !****** debug cell set here *******
          debug_flag =  .false.  
          debug_flag =  .false.  
          if ( DEBUG .and. debug_proc ) then

             debug_flag = ( debug_li == i .and. debug_lj == j ) 
             DebugCell = debug_flag
             if( debug_flag ) write(*,*) "RUNCHEM DEBUG START!"

          end if
         !write(*,"(a,4i4)") "RUNCHEM DEBUG IJTESTS", debug_li, debug_lj, i,j
         !write(*,*) "RUNCHEM DEBUG LLTESTS", me,debug_proc,debug_flag

 ! Prepare some near-surface grid and sub-scale meteorology
 ! for MicroMet
             call Get_CellMet(i,j,debug_flag) 

             call setup_1d(i,j)   

             call Add_2timing(27,tim_after,tim_before,&
                                              "Runchem:setup_1d")

             call Setup_Clouds(i,j,debug_flag)

             call setup_bio(i,j)    

             call Add_2timing(28,tim_after,tim_before,  &
                                         "Runchem:setup_cl/bio")

             call setup_phot(i,j,errcode)

             call CheckStop(errcode,"setup_photerror in Runchem") 
             call Add_2timing(29,tim_after,tim_before,  &
                                           "Runchem:1st setups")

             call setup_rcemis(i,j)

! Called every adv step, only updated every third hour
             !FUTURE call setup_nh3(i,j)    ! NH3emis, experimental (NMR-NH3)

             if ( USE_SEASALT )  &
             call SeaSalt_flux(i,j,debug_flag)

             if ( USE_DUST )     &
             call WindDust (i,j,debug_flag)


             if ( DEBUG .and. debug_flag  ) then
               call datewrite("Runchem Pre-Chem", (/ rcemis(NO,20), &
                rcbio(BIO_ISOP,KMAX_MID), rcemis(C5H8,KMAX_MID), &
                xn_2d(NO,20),xn_2d(C5H8,20) /) )
             end if

             if ( ORGANIC_AEROSOLS )  &
               call OrganicAerosol(i,j,debug_flag)

             call Add_2timing(30,tim_after,tim_before,  &
                                          "Runchem:2nd setups")

!if ( DEBUG .and. debug_flag  ) then
!    write(6,"(a16,9es10.2)") "RUNCHEM PRE-CHEM ", &
!          xn_2d(PPM25,20), xn_2d(AER_BGNDOC,20), &
!end if
!           !-------------------------------------------------
!           !-------------------------------------------------
!           !-------------------------------------------------
             call chemistry(i,j, DEBUG .and. debug_flag)
!           !-------------------------------------------------
!           !-------------------------------------------------
!           !-------------------------------------------------

             if ( DEBUG .and. debug_flag  ) then
               call datewrite("Runchem Post-Chem", &
                   (/ xn_2d(NO,20),xn_2d(C5H8,20) /) )
             end if
           !_________________________________________________

             call Add_2timing(31,tim_after,tim_before, &
                                           "Runchem:chemistry")
                
           !  Alternating Dry Deposition and Equilibrium chemistry
           !  Check that one and only one eq is chosen

                if(mod(nstep,2) /= 0 ) then 

                        if ( EQUILIB_EMEP )        call ammonium() 
                        if ( EQUILIB_MARS )        call My_MARS()
                        if ( EQUILIB_EQSAM )       call My_EQSAM() 

                        call DryDep(i,j)

                  else !do drydep first, then eq

                        call DryDep(i,j)
                        if ( EQUILIB_EMEP )        call ammonium() 
                        if ( EQUILIB_MARS )        call My_MARS()
                        if ( EQUILIB_EQSAM )       call My_EQSAM() 
                   endif
                   !????????????????????????????????????????????????????

                   call Add_2timing(32,tim_after,tim_before, &
                                                 "Runchem:ammonium+Drydep")

!                     if ( DEBUG .and. debug_flag  ) then
!                       write(6,"(a,10es12.3)") "DEBUG_RUNCHEM me RIEMER, aero", &
!                         xn_2d(SO4,20), xn_2d(aNO3,20), xn_2d(aNH4,20),tmpOut1, tmpOut2
!                       !write(6,*) "DEBUG_RUNCHEM me pre WetDep", me, prclouds_present
!                       write(6,"(a20,2i3,i5,3es12.3)") "DEBUG_RUNCHEM me OH", &
!                             current_date%day, current_date%hour,&
!                             current_date%seconds, &
!                             xn_2d(OH,20), xn_2d(O3,20), xn_2d(HNO3,20)
!
!                      end if

                     if ( prclouds_present)  &
                        call WetDeposition(i,j,debug_flag)

                      !// Calculate Aerosol Optical Depth
                      if ( USE_AOD )  &
                        call AOD_calc (i,j,debug_flag)

                   !  Modelling PM water at filter equlibration conditions:
                   !  T=20C and Rh=50% for comparability with gravimetric PM
 
                     if ( nhour == END_OF_EMEPDAY .or.  End_of_Run ) then
                        ambient = .false.
                        call Aero_water(i,j, ambient)  !
                     else
                        ambient = .true.
                        call Aero_water(i,j, ambient)
                     endif                    

                     call reset_3d(i,j)

                     call Add_2timing(33,tim_after,tim_before,&
                                            "Runchem:post stuff")

                     first_call = .false.   ! end of first call 

      end do ! j
    end do ! i

   end subroutine runchem

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

end module RunChem_ml
